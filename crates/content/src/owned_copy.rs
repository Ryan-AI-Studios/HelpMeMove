//! Keep an owned local document when it withholds or differs. This never merges.

/// Outcome of comparing an owned local document with a remote copy.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OwnedCopyDecision {
    KeepLocal,
    Unchanged,
}

/// Return `KeepLocal` when the local side withholds or the documents differ.
///
/// Equal documents with `local_withholds` false return `Unchanged`. The
/// function does not merge text or adopt the remote document.
pub fn reconcile_owned_copy(local: &str, remote: &str, local_withholds: bool) -> OwnedCopyDecision {
    if local_withholds || local != remote {
        OwnedCopyDecision::KeepLocal
    } else {
        OwnedCopyDecision::Unchanged
    }
}

#[cfg(test)]
mod tests {
    use super::{OwnedCopyDecision, reconcile_owned_copy};

    const LOCAL: &str = "{\"id\":\"owned\",\"body\":\"local\"}";
    const REMOTE: &str = "{\"id\":\"owned\",\"body\":\"remote\"}";

    #[test]
    fn withholds_true_equal_docs_keeps_local() {
        assert_eq!(
            reconcile_owned_copy(LOCAL, LOCAL, true),
            OwnedCopyDecision::KeepLocal
        );
    }

    #[test]
    fn withholds_true_different_docs_keeps_local() {
        assert_eq!(
            reconcile_owned_copy(LOCAL, REMOTE, true),
            OwnedCopyDecision::KeepLocal
        );
    }

    #[test]
    fn withholds_false_different_docs_keeps_local() {
        assert_eq!(
            reconcile_owned_copy(LOCAL, REMOTE, false),
            OwnedCopyDecision::KeepLocal
        );
    }

    #[test]
    fn withholds_false_equal_docs_unchanged() {
        assert_eq!(
            reconcile_owned_copy(LOCAL, LOCAL, false),
            OwnedCopyDecision::Unchanged
        );
    }
}
