pub fn scaffold_marker() -> &'static str {
    "helpmemove-scaffold"
}

#[cfg(test)]
mod tests {
    #[test]
    fn marker_is_stable() {
        assert_eq!(crate::scaffold_marker(), "helpmemove-scaffold");
    }
}
