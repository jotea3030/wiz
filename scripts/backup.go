package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"time"

	"cloud.google.com/go/storage"
)

// Configuration
const (
	mongoHost     = "localhost"
	mongoPort     = "27017"
	mongoDatabase = "go-mongodb"
	backupDir     = "/tmp"
)

func main() {
	// Get configuration from environment
	mongoUser := getEnv("MONGO_USER", "admin")
	mongoPassword := getEnv("MONGO_PASSWORD", "")
	bucketName := getEnv("BACKUP_BUCKET", "")

	if mongoPassword == "" {
		log.Fatal("MONGO_PASSWORD environment variable is required")
	}

	if bucketName == "" {
		log.Fatal("BACKUP_BUCKET environment variable is required")
	}

	// Create timestamp for backup file
	timestamp := time.Now().Format("20060102-150405")
	backupFile := fmt.Sprintf("%s/mongodb-backup-%s.gz", backupDir, timestamp)

	log.Printf("Starting MongoDB backup to %s", backupFile)

	// Run mongodump
	if err := runMongoDump(mongoHost, mongoPort, mongoUser, mongoPassword, backupFile); err != nil {
		log.Fatalf("Backup failed: %v", err)
	}

	log.Printf("Backup created successfully: %s", backupFile)

	// Get file size
	fileInfo, err := os.Stat(backupFile)
	if err != nil {
		log.Printf("Warning: Could not get file size: %v", err)
	} else {
		log.Printf("Backup size: %d bytes (%.2f MB)", fileInfo.Size(), float64(fileInfo.Size())/(1024*1024))
	}

	// Upload to GCS
	log.Printf("Uploading backup to GCS bucket: %s", bucketName)
	objectName := fmt.Sprintf("backup-%s.gz", timestamp)
	
	if err := uploadToGCS(backupFile, bucketName, objectName); err != nil {
		log.Fatalf("Upload failed: %v", err)
	}

	log.Printf("Backup uploaded successfully to gs://%s/%s", bucketName, objectName)

	// Clean up local backup file
	if err := os.Remove(backupFile); err != nil {
		log.Printf("Warning: Could not remove local backup file: %v", err)
	} else {
		log.Printf("Local backup file removed")
	}

	log.Println("Backup completed successfully!")
}

// runMongoDump executes mongodump command
func runMongoDump(host, port, user, password, outputFile string) error {
	cmd := exec.Command("mongodump",
		"--host", host,
		"--port", port,
		"--username", user,
		"--password", password,
		"--authenticationDatabase", "admin",
		"--archive="+outputFile,
		"--gzip",
	)

	// Capture output
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("mongodump error: %v, output: %s", err, string(output))
	}

	log.Printf("mongodump output: %s", string(output))
	return nil
}

// uploadToGCS uploads a file to Google Cloud Storage
func uploadToGCS(localFile, bucketName, objectName string) error {
	ctx := context.Background()
	
	// Create storage client
	client, err := storage.NewClient(ctx)
	if err != nil {
		return fmt.Errorf("failed to create storage client: %v", err)
	}
	defer client.Close()

	// Open local file
	f, err := os.Open(localFile)
	if err != nil {
		return fmt.Errorf("failed to open file: %v", err)
	}
	defer f.Close()

	// Get bucket handle
	bucket := client.Bucket(bucketName)
	
	// Create object writer
	ctx, cancel := context.WithTimeout(ctx, time.Minute*10)
	defer cancel()

	wc := bucket.Object(objectName).NewWriter(ctx)
	wc.ContentType = "application/gzip"
	wc.Metadata = map[string]string{
		"created": time.Now().Format(time.RFC3339),
		"source":  "mongodb-backup-script",
	}

	// Copy file content to GCS
	written, err := f.WriteTo(wc)
	if err != nil {
		return fmt.Errorf("failed to write to GCS: %v", err)
	}

	// Close writer
	if err := wc.Close(); err != nil {
		return fmt.Errorf("failed to close GCS writer: %v", err)
	}

	log.Printf("Uploaded %d bytes to GCS", written)
	return nil
}

// getEnv gets environment variable with default value
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
