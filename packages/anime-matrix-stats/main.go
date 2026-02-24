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
	"syscall"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

const (
	// Native AniMe Matrix resolution - 64x36 for 1:1 LED pixel mapping
	imgWidth  = 64
	imgHeight = 36
)

// ServerHealth tracks the health status of the server.
type ServerHealth struct {
	NodeReady   bool
	TotalPods   int
	HealthyPods int
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
		health, err := getServerHealth(clientset)
		if err != nil {
			log.Printf("Error getting server health: %v", err)
			time.Sleep(*interval)
			continue
		}

		if err := renderAndPush(health, *outputPath, *asusctlPath); err != nil {
			log.Printf("Error rendering/pushing: %v", err)
		}

		time.Sleep(*interval)
	}
}

// getServerHealth checks the node's Ready status and pod health.
func getServerHealth(clientset *kubernetes.Clientset) (*ServerHealth, error) {
	ctx := context.Background()

	health := &ServerHealth{}

	// Get the node (should be only one)
	nodes, err := clientset.CoreV1().Nodes().List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, fmt.Errorf("list nodes: %w", err)
	}

	if len(nodes.Items) > 0 {
		node := nodes.Items[0]
		for _, cond := range node.Status.Conditions {
			if cond.Type == "Ready" && cond.Status == "True" {
				health.NodeReady = true
				break
			}
		}
	}

	// Get all pods
	pods, err := clientset.CoreV1().Pods("").List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, fmt.Errorf("list pods: %w", err)
	}

	for _, pod := range pods.Items {
		if pod.DeletionTimestamp != nil {
			continue
		}
		health.TotalPods++
		if pod.Status.Phase == corev1.PodRunning || pod.Status.Phase == corev1.PodSucceeded {
			health.HealthyPods++
		}
	}

	return health, nil
}

// renderAndPush draws a single status indicator and pushes to the display.
func renderAndPush(health *ServerHealth, outputPath, asusctlPath string) error {
	img := image.NewGray(image.Rect(0, 0, imgWidth, imgHeight))

	// Fill black background
	for y := 0; y < imgHeight; y++ {
		for x := 0; x < imgWidth; x++ {
			img.SetGray(x, y, color.Gray{Y: 0})
		}
	}

	white := color.Gray{Y: 255}

	// Draw a single larger square in the visible area of the diagonal matrix
	// The right side of the image is the visible part
	cx := 46 // center X - positioned in visible area
	cy := 22 // center Y
	radius := 6

	allHealthy := health.NodeReady && health.TotalPods == health.HealthyPods

	if allHealthy {
		drawFilledSquare(img, cx, cy, radius, white)
	} else {
		drawSquareOutline(img, cx, cy, radius, white)
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

	// Push to AniMe Matrix display using pixel-image mode for 1:1 LED mapping
	cmd := exec.Command(asusctlPath, "anime", "pixel-image", "--path", outputPath)
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("asusctl anime pixel-image: %v: %s", err, output)
	}

	return nil
}

// drawFilledSquare draws a simple filled square centered at (cx, cy) with given radius.
func drawFilledSquare(img *image.Gray, cx, cy, radius int, c color.Gray) {
	for y := cy - radius; y <= cy+radius; y++ {
		for x := cx - radius; x <= cx+radius; x++ {
			if x >= 0 && x < imgWidth && y >= 0 && y < imgHeight {
				img.SetGray(x, y, c)
			}
		}
	}
}

// drawSquareOutline draws just the outline of a square.
func drawSquareOutline(img *image.Gray, cx, cy, radius int, c color.Gray) {
	left := cx - radius
	right := cx + radius
	top := cy - radius
	bottom := cy + radius

	// Draw top and bottom edges
	for x := left; x <= right; x++ {
		if x >= 0 && x < imgWidth {
			if top >= 0 && top < imgHeight {
				img.SetGray(x, top, c)
			}
			if bottom >= 0 && bottom < imgHeight {
				img.SetGray(x, bottom, c)
			}
		}
	}
	// Draw left and right edges
	for y := top; y <= bottom; y++ {
		if y >= 0 && y < imgHeight {
			if left >= 0 && left < imgWidth {
				img.SetGray(left, y, c)
			}
			if right >= 0 && right < imgWidth {
				img.SetGray(right, y, c)
			}
		}
	}
}
