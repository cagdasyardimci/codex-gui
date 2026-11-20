use super::ReportedEdit;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AppKitReviewFingerprints {
    pub path: String,
    pub file: String,
    pub hunks: Vec<(usize, String, String)>,
}

impl AppKitReviewFingerprints {
    pub(super) fn from_reports(reports: &[&ReportedEdit], net_diff: &str) -> Option<Self> {
        let last = reports.last()?;
        let path = last
            .reported_destination
            .as_deref()
            .unwrap_or(&last.reported_path);
        // AppKit groups edits by their reported destination. A composed rename chain may cover
        // more history than any one of those groups and needs a fresh review.
        if reports.iter().any(|edit| {
            edit.reported_destination
                .as_deref()
                .unwrap_or(&edit.reported_path)
                != path
        }) {
            return None;
        }
        let file = fingerprint(reports.iter().map(|edit| {
            let kind = match edit.kind {
                super::EditKind::Add => "add",
                super::EditKind::Delete => "delete",
                super::EditKind::Update => "update",
            };
            format!(
                "{}\0{}\0{kind}\0{}",
                edit.reported_path,
                edit.reported_destination.as_deref().unwrap_or(""),
                edit.diff
            )
        }));
        let combined = reports
            .iter()
            .map(|edit| edit.diff.as_str())
            .collect::<Vec<_>>()
            .join("\n");
        let old = hunk_sections(&combined);
        let mut hunks = Vec::new();
        for (index, net) in hunk_sections(net_diff).into_iter().enumerate() {
            let mut matches = old
                .iter()
                .enumerate()
                .filter(|(_, raw)| raw.trim_end_matches('\n') == net.trim_end_matches('\n'));
            if let Some((position, raw)) = matches.next()
                && matches.next().is_none()
            {
                let digest = fingerprint([*raw]);
                hunks.push((index, format!("{}-{digest}", position + 1), digest));
            }
        }
        Some(Self {
            path: path.into(),
            file,
            hunks,
        })
    }
}

fn hunk_sections(diff: &str) -> Vec<&str> {
    let mut hunks = Vec::new();
    let mut start = None;
    let mut offset = 0_usize;
    for line in diff.split_inclusive('\n') {
        if line.starts_with("diff --git ") || line.starts_with("@@ ") {
            if let Some(begin) = start.take() {
                hunks.push(&diff[begin..offset.saturating_sub(1)]);
            }
            if line.starts_with("@@ ") {
                start = Some(offset);
            }
        }
        offset += line.len();
    }
    if let Some(begin) = start {
        hunks.push(&diff[begin..]);
    }
    hunks
}

fn fingerprint(parts: impl IntoIterator<Item = impl AsRef<str>>) -> String {
    let mut hash = 14_695_981_039_346_656_037_u64;
    for part in parts {
        for byte in part.as_ref().bytes().chain([0xff]) {
            hash = (hash ^ u64::from(byte)).wrapping_mul(1_099_511_628_211);
        }
    }
    format!("{hash:x}")
}
