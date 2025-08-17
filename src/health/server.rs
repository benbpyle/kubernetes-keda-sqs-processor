use axum::{
    routing::get,
    Router,
    http::StatusCode,
    response::IntoResponse,
};
use log::info;
use std::net::SocketAddr;
use std::sync::{Arc, atomic::{AtomicBool, Ordering}};

use crate::models::HealthConfig;

/// Health check server for Kubernetes probes
#[derive(Clone)]
pub struct HealthServer {
    config: HealthConfig,
    is_ready: Arc<AtomicBool>,
}

impl HealthServer {
    /// Create a new health check server
    pub fn new(config: HealthConfig) -> Self {
        Self {
            config,
            is_ready: Arc::new(AtomicBool::new(false)),
        }
    }

    /// Set the ready state of the application
    pub fn set_ready(&self, ready: bool) {
        self.is_ready.store(ready, Ordering::SeqCst);
    }

    /// Get the ready state of the application
    #[allow(dead_code)]
    pub fn is_ready(&self) -> bool {
        self.is_ready.load(Ordering::SeqCst)
    }

    /// Start the health check server
    pub async fn start(&self) -> Result<(), Box<dyn std::error::Error>> {
        let is_ready = self.is_ready.clone();

        // Define routes
        let app = Router::new()
            .route("/health/live", get(|| async { StatusCode::OK }))
            .route("/health/ready", get(move || {
                let ready = is_ready.load(Ordering::SeqCst);
                async move {
                    if ready {
                        StatusCode::OK.into_response()
                    } else {
                        StatusCode::SERVICE_UNAVAILABLE.into_response()
                    }
                }
            }));

        // Bind to address
        let addr = format!("{}:{}", self.config.host, self.config.port)
            .parse::<SocketAddr>()
            .expect("Failed to parse socket address");

        info!("Health check server listening on {}", addr);

        // Start server
        axum::Server::bind(&addr)
            .serve(app.into_make_service())
            .await?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_health_server_ready_state() {
        let config = HealthConfig {
            host: "127.0.0.1".to_string(),
            port: 8080,
        };

        let server = HealthServer::new(config);

        // Default state should be not ready
        assert_eq!(server.is_ready(), false);

        // Set to ready
        server.set_ready(true);
        assert_eq!(server.is_ready(), true);

        // Set back to not ready
        server.set_ready(false);
        assert_eq!(server.is_ready(), false);
    }
}
