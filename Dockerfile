# Planner stage - Use cargo-chef to create a recipe.json
FROM rust:1.80-slim AS planner
WORKDIR /app
RUN cargo install cargo-chef
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

# Builder stage - Build dependencies and application
FROM rust:1.80-slim AS builder
WORKDIR /app
RUN cargo install cargo-chef
COPY --from=planner /app/recipe.json recipe.json
# Build dependencies - this is the caching layer
RUN cargo chef cook --release --recipe-path recipe.json
# Build application - this will only rebuild when the source code changes
COPY . .
RUN cargo build --release

# Runtime stage
FROM debian:bookworm-slim AS runtime
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
