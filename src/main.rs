use anyhow::{Context, Result};
use aws_config::meta::region::RegionProviderChain;
use aws_sdk_sqs::Client as SqsClient;
use futures_util::StreamExt;
use log::{error, info};
use signal_hook::consts::TERM_SIGNALS;
use signal_hook_tokio::Signals;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use tokio::time::{sleep, Duration};

mod health;
mod models;
mod services;

use health::HealthServer;
use models::Config;
use services::SqsService;

/// Initialize the logger
fn init_logger(log_level: &str) {
    let env = env_logger::Env::default().filter_or("RUST_LOG", log_level);
    env_logger::Builder::from_env(env).init();
}

/// Load configuration
fn load_config() -> Result<Config> {
    // For simplicity, we're using default config
    // In a real application, you would load from environment variables or a config file
    Ok(Config::default())
}

/// Initialize AWS SQS client
async fn init_sqs_client() -> Result<SqsClient> {
    let region_provider = RegionProviderChain::default_provider();
    let config = aws_config::from_env().region(region_provider).load().await;
    Ok(SqsClient::new(&config))
}

/// Handle termination signals
async fn handle_signals(
    mut signals: Signals,
    shutdown_flag: Arc<AtomicBool>,
) -> Result<(), Box<dyn std::error::Error>> {
    while let Some(signal) = signals.next().await {
        info!("Received signal: {}", signal);
        shutdown_flag.store(true, Ordering::SeqCst);
    }
    Ok(())
}

/// Main application logic
async fn run_app() -> Result<()> {
    // Load configuration
    let config = load_config().context("Failed to load configuration")?;

    // Initialize logger
    init_logger(&config.logging.level);
    info!("Starting SQS processor");

    // Initialize shutdown flag
    let shutdown_flag = Arc::new(AtomicBool::new(false));

    // Register signal handlers
    let signals = Signals::new(TERM_SIGNALS)?;
    let signals_handle = signals.handle();
    let shutdown_flag_clone = shutdown_flag.clone();

    // Spawn signal handler task
    let signal_task = tokio::spawn(async move {
        if let Err(e) = handle_signals(signals, shutdown_flag_clone).await {
            error!("Error in signal handler: {}", e);
        }
    });

    // Initialize SQS client
    let sqs_client = init_sqs_client().await.context("Failed to initialize SQS client")?;
    let sqs_service = SqsService::new(sqs_client, config.sqs.clone());

    // Initialize health server
    let health_server = Arc::new(HealthServer::new(config.health.clone()));
    let health_server_clone = health_server.clone();

    // Spawn health server task
    let health_server_task = tokio::spawn(async move {
        if let Err(e) = health_server_clone.start().await {
            error!("Health server error: {}", e);
        }
    });

    // Set application as ready
    health_server.set_ready(true);
    info!("Application is ready");

    // Main processing loop
    while !shutdown_flag.load(Ordering::SeqCst) {
        // Poll for messages
        match sqs_service.poll_messages().await {
            Ok(messages) => {
                if !messages.is_empty() {
                    // Process messages
                    if let Err(e) = sqs_service.process_messages(messages).await {
                        error!("Error processing messages: {}", e);
                    }
                }
            }
            Err(e) => {
                error!("Error polling messages: {}", e);
                // Add a small delay before retrying to avoid hammering the SQS service
                sleep(Duration::from_secs(1)).await;
            }
        }
    }

    // Graceful shutdown
    info!("Shutting down gracefully...");
    health_server.set_ready(false);

    // Cancel signal handler
    signals_handle.close();

    // Wait for tasks to complete
    let _ = signal_task.await;
    let _ = health_server_task.await;

    info!("Shutdown complete");
    Ok(())
}

#[tokio::main]
async fn main() {
    if let Err(e) = run_app().await {
        error!("Application error: {}", e);
        std::process::exit(1);
    }
}
