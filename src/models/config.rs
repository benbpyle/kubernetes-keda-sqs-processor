use serde::Deserialize;

/// Application configuration
#[derive(Debug, Deserialize, Clone)]
pub struct Config {
    /// AWS SQS configuration
    pub sqs: SqsConfig,
    /// Health check server configuration
    pub health: HealthConfig,
    /// Logging configuration
    pub logging: LoggingConfig,
}

/// AWS SQS configuration
#[derive(Debug, Deserialize, Clone)]
pub struct SqsConfig {
    /// SQS queue URL to poll
    pub queue_url: String,
    /// Maximum number of messages to receive in one batch
    pub max_messages: i32,
    /// Wait time in seconds for long polling
    pub wait_time_seconds: i32,
    /// Visibility timeout in seconds
    pub visibility_timeout: i32,
}

/// Health check server configuration
#[derive(Debug, Deserialize, Clone)]
pub struct HealthConfig {
    /// Host to bind the health check server to
    pub host: String,
    /// Port to bind the health check server to
    pub port: u16,
}

/// Logging configuration
#[derive(Debug, Deserialize, Clone)]
pub struct LoggingConfig {
    /// Log level (trace, debug, info, warn, error)
    pub level: String,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            sqs: SqsConfig {
                queue_url: String::from(""),
                max_messages: 10,
                wait_time_seconds: 20,
                visibility_timeout: 30,
            },
            health: HealthConfig {
                host: String::from("0.0.0.0"),
                port: 8080,
            },
            logging: LoggingConfig {
                level: String::from("info"),
            },
        }
    }
}