//! Who is asking, and may they. Access says who signed in; D1 says whether they may use the site, and as what.

use crate::access::{Audience, Claims};
use crate::store::{Role, Store};

/// What a route needs. Admin routes also need the admin Access application (GitHub with a passkey), so
/// the owner signing in with an email PIN can't reach them.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Need {
    Reviewer,
    Admin,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Principal {
    pub email: String,
    pub display_name: String,
    pub role: Role,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Denied {
    Unauthenticated,
    Forbidden,
}

/// Trimmed and lowercased, or `None` unless it has exactly one `@` with text on both sides, no whitespace
/// and at most 254 characters.
pub fn normalize_email(raw: &str) -> Option<String> {
    let email = raw.trim().to_lowercase();
    let (local, domain) = email.split_once('@')?;
    let valid = !local.is_empty()
        && !domain.is_empty()
        && !domain.contains('@')
        && !email.chars().any(char::is_whitespace)
        && email.chars().count() <= 254;
    valid.then_some(email)
}

/// The signed-in user, if they may do what `need` asks. Fails closed: a service token (no email), an
/// unknown or inactive user, the wrong application or role, and a store error are all `Forbidden`.
pub async fn authorize<S: Store>(
    claims: &Claims,
    audience: Audience,
    need: Need,
    store: &S,
) -> Result<Principal, Denied> {
    let email = claims
        .email
        .as_deref()
        .and_then(normalize_email)
        .ok_or(Denied::Forbidden)?;
    let user = match store.user(&email).await {
        Ok(Some(user)) if user.active => user,
        _ => return Err(Denied::Forbidden),
    };
    if need == Need::Admin && (audience != Audience::Admin || user.role != Role::Admin) {
        return Err(Denied::Forbidden);
    }
    Ok(Principal {
        email: user.email,
        display_name: user.display_name,
        role: user.role,
    })
}
