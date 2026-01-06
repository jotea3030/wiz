# Multi-stage build for Go application
FROM golang:1.21-alpine AS builder

# Install git
RUN apk add --no-cache git

# Set working directory
WORKDIR /build

# Clone the todo app
RUN git clone https://github.com/dogukanozdemir/golang-todo-mongodb.git .

# Remove vendor directory if it exists
RUN rm -rf vendor

# Fix unused import in main.go
RUN sed -i '/^[[:space:]]*"os"$/d' main.go

# Download dependencies
RUN go mod download

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main .

# Final stage - minimal image
FROM alpine:3.18

# Install ca-certificates for HTTPS
RUN apk --no-cache add ca-certificates

# Create app directory
WORKDIR /app

# Copy binary from builder
COPY --from=builder /build/main .

# Copy static assets
COPY --from=builder /build/assets ./assets

# Copy wizexercise.txt file (REQUIRED FOR WIZ EXERCISE)
COPY docker/wizexercise.txt /app/wizexercise.txt

# Create empty .env file (app expects it but we use k8s secrets)
RUN touch /app/.env

# Verify file exists during build
RUN cat /app/wizexercise.txt && echo "wizexercise.txt verified in container"

# Create non-root user
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser && \
    chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/ || exit 1

# Run the application
CMD ["./main"]
