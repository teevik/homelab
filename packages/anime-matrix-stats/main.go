package main

import (
	"context"
	"flag"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"sort"
	"syscall"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

const (
	imgWidth  = 192
	imgHeight = 108
)

// NodeHealth tracks the health status of a single node.
type NodeHealth struct {
	Name    string
	Healthy bool
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

	// Handle graceful shutdown
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
		healths, err := getNodeHealths(clientset)
		if err != nil {
			log.Printf("Error getting node healths: %v", err)
			time.Sleep(*interval)
			continue
		}

		if err := renderAndPush(healths, *outputPath, *asusctlPath); err != nil {
			log.Printf("Error rendering/pushing: %v", err)
		}

		time.Sleep(*interval)
	}
}

// getNodeHealths checks each node's Ready status and whether all pods on it are Running/Succeeded.
func getNodeHealths(clientset *kubernetes.Clientset) ([]NodeHealth, error) {
	ctx := context.Background()

	// Get all nodes
	nodes, err := clientset.CoreV1().Nodes().List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, fmt.Errorf("list nodes: %w", err)
	}

	// Sort nodes by name for consistent ordering
	sort.Slice(nodes.Items, func(i, j int) bool {
		return nodes.Items[i].Name < nodes.Items[j].Name
	})

	// Get all pods across all namespaces
	pods, err := clientset.CoreV1().Pods("").List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, fmt.Errorf("list pods: %w", err)
	}

	// Group pods by node
	podsByNode := make(map[string][]corev1.Pod)
	for _, pod := range pods.Items {
		if pod.Spec.NodeName != "" {
			podsByNode[pod.Spec.NodeName] = append(podsByNode[pod.Spec.NodeName], pod)
		}
	}

	healths := make([]NodeHealth, 0, len(nodes.Items))
	for _, node := range nodes.Items {
		health := NodeHealth{Name: node.Name}

		// Check if node is Ready
		nodeReady := false
		for _, cond := range node.Status.Conditions {
			if cond.Type == "Ready" && cond.Status == "True" {
				nodeReady = true
				break
			}
		}

		if !nodeReady {
			// Node not ready = unhealthy
			health.Healthy = false
			healths = append(healths, health)
			continue
		}

		// Check all pods on this node
		nodePods := podsByNode[node.Name]
		allPodsHealthy := true
		for _, pod := range nodePods {
			// Skip pods that are being deleted
			if pod.DeletionTimestamp != nil {
				continue
			}
			// Only Running and Succeeded phases are considered healthy
			if pod.Status.Phase != corev1.PodRunning && pod.Status.Phase != corev1.PodSucceeded {
				allPodsHealthy = false
				break
			}
		}

		health.Healthy = allPodsHealthy
		healths = append(healths, health)
	}

	return healths, nil
}

// renderAndPush draws three circles (filled for healthy, empty for unhealthy) and pushes to the display.
func renderAndPush(healths []NodeHealth, outputPath, asusctlPath string) error {
	img := image.NewGray(image.Rect(0, 0, imgWidth, imgHeight))

	// Fill black background
	for y := 0; y < imgHeight; y++ {
		for x := 0; x < imgWidth; x++ {
			img.SetGray(x, y, color.Gray{Y: 0})
		}
	}

	white := color.Gray{Y: 255}

	// Draw three circles horizontally centered
	// Circle radius: 28px, spaced 64px apart
	// Centers at: x=32, x=96, x=160 (for 3 nodes)
	// All at y=54 (vertical center of 108px height)
	centers := []int{32, 96, 160}
	radius := 28

	for i, health := range healths {
		if i >= len(centers) {
			break // Only show first 3 nodes
		}
		cx := centers[i]
		cy := 54
		if health.Healthy {
			drawFilledCircle(img, cx, cy, radius, white)
		} else {
			drawCircleOutline(img, cx, cy, radius, 3, white)
		}
	}

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

// drawFilledCircle draws a filled circle using midpoint circle algorithm.
func drawFilledCircle(img *image.Gray, cx, cy, radius int, c color.Gray) {
	x := radius
	y := 0
	err := 0

	for x >= y {
		// Draw horizontal lines between symmetric points
		for dx := cx - x; dx <= cx+x; dx++ {
			img.SetGray(dx, cy+y, c)
			img.SetGray(dx, cy-y, c)
		}
		for dx := cx - y; dx <= cx+y; dx++ {
			img.SetGray(dx, cy+x, c)
			img.SetGray(dx, cy-x, c)
		}

		if err <= 0 {
			y++
			err += 2*y + 1
		}
		if err > 0 {
			x--
			err -= 2*x + 1
		}
	}
}

// drawCircleOutline draws just the outline of a circle with a given stroke width.
func drawCircleOutline(img *image.Gray, cx, cy, radius, stroke int, c color.Gray) {
	// Draw multiple concentric circles for the stroke
	for r := radius - stroke/2; r <= radius+stroke/2; r++ {
		if r < 0 {
			continue
		}
		x := r
		y := 0
		err := 0

		for x >= y {
			// Set 8 symmetric points
			points := [][2]int{
				{cx + x, cy + y}, {cx + y, cy + x},
				{cx - y, cy + x}, {cx - x, cy + y},
				{cx - x, cy - y}, {cx - y, cy - x},
				{cx + y, cy - x}, {cx + x, cy - y},
			}
			for _, p := range points {
				if p[0] >= 0 && p[0] < imgWidth && p[1] >= 0 && p[1] < imgHeight {
					img.SetGray(p[0], p[1], c)
				}
			}

			if err <= 0 {
				y++
				err += 2*y + 1
			}
			if err > 0 {
				x--
				err -= 2*x + 1
			}
		}
	}
}
