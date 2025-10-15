use thiserror::Error;

/// Common error type for the crypto crate FFI surface.
#[derive(Debug, Error)]
pub enum CryptoError {
    #[error("unsupported operation: {0}")]
    Unsupported(&'static str),
    #[error("serialization failed: {0}")]
    Serialization(String),
    #[error("signal primitive failed: {0}")]
    Signal(String),
}

pub type CryptoResult<T> = Result<T, CryptoError>;

impl From<serde_json::Error> for CryptoError {
    fn from(value: serde_json::Error) -> Self {
        CryptoError::Serialization(value.to_string())
    }
}
