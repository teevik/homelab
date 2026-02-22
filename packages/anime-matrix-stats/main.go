package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
	"time"

	"golang.org/x/image/font"
	"golang.org/x/image/font/basicfont"
	"golang.org/x/image/math/fixed"

	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

const (
	// Image dimensions - 192x108 gives ~3x oversampling of the ~64x36 effective
	// AniMe Matrix resolution, which works well for text rendering with basicfont.
	imgWidth  = 192
	imgHeight = 108
)

// ClusterStats holds the collected cluster metrics.
type ClusterStats struct {
	NodesReady int
	NodesTotal int
	CPUPercent float64
	MemPercent float64
}

func main() {
	kubeconfig := flag.String("kubeconfig", "/etc/rancher/k3s/k3s.yaml", "path to kubeconfig")
	interval := flag.Duration("interval", 15*time.Second, "refresh interval")
	asusctlPath := flag.String("asusctl", "asusctl", "path to asusctl binary")
	outputPath := flag.String("output", "/tmp/anime-matrix-stats.png", "path to output image")
	flag.Parse()

	config, err := clientcmd.BuildConfigFromFlags("", *kubeconfig)
	if err != nil {
		log.Fatalf("Failed to build kubeconfig: %v", err)
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatalf("Failed to create kubernetes client: %v", err)
	}

	// Handle graceful shutdown - turn off the display
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigCh
		log.Println("Shutting down, disabling AniMe Matrix display...")
		_ = exec.Command(*asusctlPath, "anime", "--enable-display", "false").Run()
		os.Exit(0)
	}()

	// Enable the display on startup
	if err := exec.Command(*asusctlPath, "anime", "--enable-display", "true").Run(); err != nil {
		log.Printf("Warning: failed to enable anime display: %v", err)
	}

	log.Printf("Starting anime-matrix-stats (interval=%s)", *interval)

	for {
		stats, err := getClusterStats(clientset)
		if err != nil {
			log.Printf("Error getting cluster stats: %v", err)
			time.Sleep(*interval)
			continue
		}

		if err := renderAndPush(stats, *outputPath, *asusctlPath); err != nil {
			log.Printf("Error rendering/pushing: %v", err)
		}

		time.Sleep(*interval)
	}
}

// getClusterStats collects node status and resource usage from the cluster.
func getClusterStats(clientset *kubernetes.Clientset) (*ClusterStats, error) {
	ctx := context.Background()

	// Get nodes
	nodes, err := clientset.CoreV1().Nodes().List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, fmt.Errorf("list nodes: %w", err)
	}

	stats := &ClusterStats{
		NodesTotal: len(nodes.Items),
	}

	var totalAllocatableCPU, totalAllocatableMem int64

	for _, node := range nodes.Items {
		for _, cond := range node.Status.Conditions {
			if cond.Type == "Ready" && cond.Status == "True" {
				stats.NodesReady++
			}
		}
		totalAllocatableCPU += node.Status.Allocatable.Cpu().MilliValue()
		totalAllocatableMem += node.Status.Allocatable.Memory().Value()
	}

	// Fetch node metrics from the metrics API (requires metrics-server)
	result := clientset.RESTClient().
		Get().
		AbsPath("/apis/metrics.k8s.io/v1beta1/nodes").
		Do(ctx)

	rawData, err := result.Raw()
	if err != nil {
		log.Printf("Warning: metrics unavailable (is metrics-server running?): %v", err)
		return stats, nil
	}

	var metricsResponse struct {
		Items []struct {
			Usage struct {
				CPU    string `json:"cpu"`
				Memory string `json:"memory"`
			} `json:"usage"`
		} `json:"items"`
	}

	if err := json.Unmarshal(rawData, &metricsResponse); err != nil {
		log.Printf("Warning: failed to parse metrics response: %v", err)
		return stats, nil
	}

	var totalUsedCPU, totalUsedMem int64
	for _, item := range metricsResponse.Items {
		if cpuQty, err := resource.ParseQuantity(item.Usage.CPU); err == nil {
			totalUsedCPU += cpuQty.MilliValue()
		}
		if memQty, err := resource.ParseQuantity(item.Usage.Memory); err == nil {
			totalUsedMem += memQty.Value()
		}
	}

	if totalAllocatableCPU > 0 {
		stats.CPUPercent = float64(totalUsedCPU) / float64(totalAllocatableCPU) * 100
	}
	if totalAllocatableMem > 0 {
		stats.MemPercent = float64(totalUsedMem) / float64(totalAllocatableMem) * 100
	}

	return stats, nil
}

// renderAndPush renders the stats to a PNG image and pushes it to the AniMe Matrix.
func renderAndPush(stats *ClusterStats, outputPath, asusctlPath string) error {
	img := image.NewGray(image.Rect(0, 0, imgWidth, imgHeight))

	// Fill black background
	for y := 0; y < imgHeight; y++ {
		for x := 0; x < imgWidth; x++ {
			img.SetGray(x, y, color.Gray{Y: 0})
		}
	}

	white := color.Gray{Y: 255}
	dim := color.Gray{Y: 100}

	// Draw title
	drawString(img, 4, 14, "K3S CLUSTER", white)

	// Draw separator line
	for x := 4; x < imgWidth-4; x++ {
		img.SetGray(x, 20, dim)
	}

	// Draw node status
	nodeStr := fmt.Sprintf("NODES  %d/%d", stats.NodesReady, stats.NodesTotal)
	nodeColor := white
	if stats.NodesReady < stats.NodesTotal {
		nodeColor = color.Gray{Y: 180} // slightly dimmer if degraded
	}
	drawString(img, 4, 38, nodeStr, nodeColor)

	// Draw node status indicator dots
	dotY := 32
	for i := 0; i < stats.NodesTotal; i++ {
		dotX := imgWidth - 20 + (i * 6)
		c := white
		if i >= stats.NodesReady {
			c = dim
		}
		drawDot(img, dotX, dotY, c)
	}

	// Draw CPU bar
	drawString(img, 4, 58, fmt.Sprintf("CPU  %3.0f%%", stats.CPUPercent), white)
	drawBar(img, 80, 50, 104, 10, stats.CPUPercent/100.0, white, dim)

	// Draw memory bar
	drawString(img, 4, 78, fmt.Sprintf("MEM  %3.0f%%", stats.MemPercent), white)
	drawBar(img, 80, 70, 104, 10, stats.MemPercent/100.0, white, dim)

	// Draw bottom separator
	for x := 4; x < imgWidth-4; x++ {
		img.SetGray(x, 88, dim)
	}

	// Draw timestamp
	timeStr := time.Now().Format("15:04:05")
	drawString(img, 4, 102, timeStr, dim)

	// Write PNG
	f, err := os.Create(outputPath)
	if err != nil {
		return fmt.Errorf("create output file: %w", err)
	}
	defer f.Close()

	if err := png.Encode(f, img); err != nil {
		return fmt.Errorf("encode png: %w", err)
	}

	// Push to AniMe Matrix display
	cmd := exec.Command(asusctlPath, "anime", "image", "--path", outputPath)
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("asusctl anime image: %v: %s", err, output)
	}

	return nil
}

// drawString renders text onto a grayscale image using basicfont.
func drawString(img *image.Gray, x, y int, text string, c color.Gray) {
	point := fixed.Point26_6{
		X: fixed.I(x),
		Y: fixed.I(y),
	}
	d := &font.Drawer{
		Dst:  img,
		Src:  image.NewUniform(c),
		Face: basicfont.Face7x13,
		Dot:  point,
	}
	d.DrawString(text)
}

// drawBar renders a horizontal progress bar.
func drawBar(img *image.Gray, x, y, width, height int, fill float64, fg, bg color.Gray) {
	if fill < 0 {
		fill = 0
	}
	if fill > 1 {
		fill = 1
	}
	fillWidth := int(float64(width) * fill)

	for dy := 0; dy < height; dy++ {
		for dx := 0; dx < width; dx++ {
			px := x + dx
			py := y + dy
			// Border
			if dy == 0 || dy == height-1 || dx == 0 || dx == width-1 {
				img.SetGray(px, py, bg)
			} else if dx <= fillWidth {
				img.SetGray(px, py, fg)
			}
		}
	}
}

// drawDot renders a small filled circle (3x3).
func drawDot(img *image.Gray, cx, cy int, c color.Gray) {
	img.SetGray(cx, cy-1, c)
	img.SetGray(cx-1, cy, c)
	img.SetGray(cx, cy, c)
	img.SetGray(cx+1, cy, c)
	img.SetGray(cx, cy+1, c)
}
