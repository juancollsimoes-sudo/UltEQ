pub mod linux_pw;
pub mod windows_apo;

#[derive(Debug, Clone, PartialEq)]
pub enum FilterType {
    Peaking,
    LowShelf,
    HighShelf,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Filter {
    pub filter_type: FilterType,
    pub fc: f32,
    pub gain: f32,
    pub q: f32,
}
