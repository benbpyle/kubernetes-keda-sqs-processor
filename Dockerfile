# Build stage
FROM rust:1.80-slim AS builder

WORKDIR /app

# Copy manifests
COPY Cargo.toml Cargo.lock ./

# Create a dummy main.rs to build dependencies
RUN mkdir -p src && \
    echo 'fn main() { println!("Hello, world!"); }' > src/main.rs && \
    cargo build --release || true && \
    rm -rf src

# Copy source code
COPY . .

# Build the application
RUN cargo build --release

# Runtime stage
FROM debian:bullseye-slim AS runtime

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Copy the binary from the builder stage
COPY --from=builder /app/target/release/sqs-processor /app/sqs-processor

# Set environment variables
ENV RUST_LOG=info

# Expose health check port
EXPOSE 8080

# Run the application
CMD ["/app/sqs-processor"]
