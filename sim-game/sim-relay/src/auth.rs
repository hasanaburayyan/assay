//! Who is connecting. The relay only ever sees an `AccountId`, so swapping
//! the dev authenticator for a Steam one later changes nothing else.

use std::fmt;

/// A global identity: `dev:ada` today, `steam:7656…` later. Distinct from
/// `PlayerId`, which is a slot inside one world; the relay maps between them.
#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct AccountId(pub String);

impl fmt::Display for AccountId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

pub trait Authenticator {
    /// Decide who a connecting client is, or refuse them with a reason.
    /// A Steam version will verify a session ticket sent in `Hello`.
    fn authenticate(&self, name: &str) -> Result<AccountId, String>;
}

/// Trusts whatever name the client sends. For development and LAN play only.
pub struct DevAuthenticator;

impl Authenticator for DevAuthenticator {
    fn authenticate(&self, name: &str) -> Result<AccountId, String> {
        let valid_chars = name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');
        if name.is_empty() || name.len() > 20 || !valid_chars {
            return Err(
                "Names must be 1-20 characters: letters, numbers, - or _. Try --name ada.".into(),
            );
        }
        Ok(AccountId(format!("dev:{}", name.to_lowercase())))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dev_accounts_ignore_case() {
        let auth = DevAuthenticator;
        assert_eq!(
            auth.authenticate("Ada").unwrap(),
            AccountId("dev:ada".into())
        );
        assert_eq!(
            auth.authenticate("ada").unwrap(),
            AccountId("dev:ada".into())
        );
    }

    #[test]
    fn bad_names_are_refused() {
        let auth = DevAuthenticator;
        for bad in ["", "has space", "way-too-long-for-a-player-name", "émile"] {
            assert!(auth.authenticate(bad).is_err(), "{bad:?} should be refused");
        }
    }
}
