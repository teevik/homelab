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
	// Native AniMe Matrix resolution - 64x36 for 1:1 LED pixel mapping
	// This maps 1:1 to the actual LED grid when using pixel-image mode
	imgWidth  = 64
	imgHeight = 36
)

// flipY converts a Y coordinate from top-origin to bottom-origin (flips image vertically)
func flipY(y int) int {
	return imgHeight - 1 - y
}

// Compact 3x5 bitmap font for digits 1-3 for 64x36 native resolution
// Each digit is represented as 5 rows of 3 bits - optimized for LED matrix
var digitBitmaps = map[rune][5][3]bool{
	'1': {
		{false, true, false},
		{true, true, false},
		{false, true, false},
		{false, true, false},
		{true, true, true},
	},
	'2': {
		{true, true, true},
		{false, false, true},
		{true, true, true},
		{true, false, false},
		{true, true, true},
	},
	'3': {
		{true, true, true},
		{false, false, true},
		{true, true, true},
		{false, false, true},
		{true, true, true},
	},
}

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

// renderAndPush draws three circles with numbers above them and pushes to the display.
func renderAndPush(healths []NodeHealth, outputPath, asusctlPath string) error {
	img := image.NewGray(image.Rect(0, 0, imgWidth, imgHeight))

	// Fill black background
	for y := 0; y < imgHeight; y++ {
		for x := 0; x < imgWidth; x++ {
			img.SetGray(x, y, color.Gray{Y: 0})
		}
	}

	white := color.Gray{Y: 255}

	// Layout: Positioned in the VISIBLE area of the diagonal matrix
	// The diagonal matrix shows a triangle - right side is visible, left is cut off
	// We need to draw in the RIGHT portion of the image to be visible
	// Three circles with compact 3x5 numbers above (upside down to appear right-side up)
	// Square radius: 3px (7x7 pixels total), spaced 12px apart
	// Centers at: x=52, x=40, x=28 (REVERSED - right to left to fix horizontal flip)
	// Square center at y=26 (moved down toward bottom edge)
	// Numbers at y=35 (4 pixel padding from square)
	centers := []int{52, 40, 28}
	radius := 3
	circleY := 26 // center Y for squares (moved down toward bottom)
	numY := 35    // bottom of numbers (moved down with squares)

	for i, health := range healths {
		if i >= len(centers) {
			break // Only show first 3 nodes
		}

		cx := centers[i]

		// Draw number above square (1, 2, or 3) - right aligned with the square
		digit := rune('1' + i)
		if bitmap, ok := digitBitmaps[digit]; ok {
			// Right align: square right edge at cx+3, digit (3px) ends at cx+4, so starts at cx+2
			drawBitmapDigit(img, cx+2, numY, bitmap, white)
		}

		// Draw simple square below number - direct coordinates, NO flipY
		if health.Healthy {
			drawFilledSquare(img, cx, circleY, radius, white)
		} else {
			drawSquareOutline(img, cx, circleY, radius, white)
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

	// Push to AniMe Matrix display using pixel-image mode for 1:1 LED mapping
	cmd := exec.Command(asusctlPath, "anime", "pixel-image", "--path", outputPath)
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("asusctl anime pixel-image: %v: %s", err, output)
	}

	return nil
}

// drawBitmapDigit draws a 3x5 digit at the specified position.
// Digits are drawn upside-down and horizontally-flipped to appear correctly on the diagonal matrix.
func drawBitmapDigit(img *image.Gray, x, y int, bitmap [5][3]bool, c color.Gray) {
	// Draw upside down and horizontally flipped
	// row 0 at bottom (y), grows upward (decreasing y)
	// columns reversed (2-col, 1-col, 0-col) to flip horizontally
	for row := 0; row < 5; row++ {
		for col := 0; col < 3; col++ {
			if bitmap[row][col] {
				// Flip horizontally: col 0→2, col 1→1, col 2→0
				px := x + (2 - col)
				py := y - row // Subtract row to go upward (flipped)

				if px >= 0 && px < imgWidth && py >= 0 && py < imgHeight {
					img.SetGray(px, py, c)
				}
			}
		}
	}
}

// drawFilledSquare draws a simple filled square centered at (cx, cy) with given radius.
// Radius is half the side length (square spans from cx-radius to cx+radius).
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
// Radius is half the side length.
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
