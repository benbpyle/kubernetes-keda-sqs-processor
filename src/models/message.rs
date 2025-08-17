use aws_sdk_sqs::types::Message as SqsMessage;
use serde::{Deserialize, Serialize};

/// Represents a message from SQS
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    /// The message ID from SQS
    pub message_id: String,
    /// The receipt handle used to delete the message
    pub receipt_handle: String,
    /// The message body
    pub body: String,
    /// Message attributes
    pub attributes: std::collections::HashMap<String, String>,
}

impl From<SqsMessage> for Message {
    fn from(msg: SqsMessage) -> Self {
        let mut attributes = std::collections::HashMap::new();

        // Extract message attributes if any
        if let Some(attrs) = msg.attributes() {
            for (key, value) in attrs {
                attributes.insert(key.as_str().to_string(), value.to_string());
            }
        }

        Self {
            message_id: msg.message_id().unwrap_or_default().to_string(),
            receipt_handle: msg.receipt_handle().unwrap_or_default().to_string(),
            body: msg.body().unwrap_or_default().to_string(),
            attributes,
        }
    }
}
