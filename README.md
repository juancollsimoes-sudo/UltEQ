# UltEQ - Surgical Audio Precision 🎧

UltEQ is a next-generation system-wide parametric equalizer designed for audiophiles, audio engineers, and enthusiasts. Built with a lightning-fast **Rust** digital signal processing (DSP) backend and a fluid, cross-platform **Flutter** frontend, UltEQ allows you to apply surgical, high-fidelity acoustic corrections directly to your operating system's audio server.

![UltEQ Interface Preview](https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/logo.png) *(UI Screenshot placeholder)*

## ✨ Features

* **Surgical Parametric AutoEq:** Forget naive graphic equalizers. UltEQ incorporates an advanced Peak Finding & Fitting algorithm (similar to Room EQ Wizard) that mathematically scans the error curve between your headphones and your target, calculating exact Q-values, gains, and frequencies to flatten peaks and dips perfectly without "clustering" filters.
* **System-Wide Linux Integration:** Thanks to native PipeWire integrations, UltEQ generates and injects `libspa-audioconvert` biquad filter chains directly into your Linux audio server. No virtual cables or clunky routing needed.
* **Massive Headphone Database:** Includes a deeply integrated SQLite database with thousands of raw measurements and industry-standard target curves (Harman, IEF Neutral, Oratory1990) sourced directly from the AutoEq project.
* **Real-time Logarithmic Canvas:** A fully interactive, 60fps canvas to visually sculpt your audio. Drag parametric nodes, adjust bandwidths, and watch your final frequency response curve update instantly.
* **Dynamic Target Morphing:** Dynamically adjust the tilt, bass boost, ear gain, and treble of your target curve. The AutoEq engine will automatically adapt its filters to match your customized target.

## 🏗️ Architecture

UltEQ bridges two powerful ecosystems:
1. **`rust_core`**: A low-level audio processing library. It handles SQLite database querying, FFI bindings, complex math for peaking/shelf filter responses, the greedy peak-fitting AutoEq algorithm, and direct PipeWire configuration generation.
2. **`flutter_app`**: A reactive, modern desktop interface that communicates directly with the Rust backend via zero-copy FFI (`flutter_rust_bridge`).

## 🚀 Getting Started (Linux)

### Prerequisites
* **Flutter SDK** (Version 3.19+)
* **Rust Toolchain** (`cargo`)
* **PipeWire** (Active sound server)

### Building and Running

1. **Clone the repository:**
   ```bash
   git clone https://github.com/juancollsimoes-sudo/UltEQ.git
   cd UltEQ
   ```

2. **Run the application:**
   Since the FFI bindings are pre-generated, you can directly run the Flutter app. Cargo will automatically compile the Rust `.so` library during the Flutter build process.
   ```bash
   cd flutter_app
   flutter run -d linux
   ```

## 🛠️ Usage

1. **Select a Headphone:** Use the right sidebar to search the database for your specific headphone model.
2. **Choose a Target:** Select a target curve (e.g., IEF Neutral in-ear) from the bottom left panel.
3. **AutoEq:** Click the **AutoEq** button in the top header. The Rust engine will instantly calculate the optimal Parametric EQ filters (distributed perfectly between 20Hz and 6000Hz) to match your headphones to the target.
4. **Apply EQ:** Click **Apply EQ**. UltEQ will seamlessly restart a background PipeWire daemon, injecting your filters system-wide.

## 🤝 Acknowledgments

* **[AutoEq by jaakkopasanen](https://github.com/jaakkopasanen/AutoEq)** - For the incredible database of headphone measurements and the acoustic inspiration behind the peak-fitting algorithms.
* **flutter_rust_bridge** - For making Dart-to-Rust communication seamless.

## 📄 License

This project is licensed under the MIT License.
