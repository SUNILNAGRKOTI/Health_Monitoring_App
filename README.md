
# Health Monitoring App

Your Personal Health Assistant

Track, analyze, and improve your health with advanced insights, beautiful charts, and seamless notifications.

---

## Features

- Secure Login & Sign Up (Firebase Auth & Google Sign-In)
- Splash Screen
- Health Data Tracking & Visualization (charts, graphs)
- AI Health Assistant (Gemini AI integration)
- Camera-based Heart Rate Scanner
- Smart Notifications & Reminders
- Local & Cloud Data Storage
- PDF Report Generation
- Dark & Light Mode
- Responsive UI for all devices

---

## Screenshots


<div align="center">
  <table>
    <tr>
      <td align="center"><b>Login</b><br><img src="project_images/21.jpeg" alt="Login Screen" width="180"/></td>
      <td align="center"><b>Sign Up</b><br><img src="project_images/22.jpeg" alt="Sign Up Screen" width="180"/></td>
      <td align="center"><b>Splash</b><br><img src="project_images/WhatsApp%20Image%202026-03-16%20at%207.14.45%20PM.jpeg" alt="Splash Screen" width="180"/></td>
    </tr>
    <tr>
      <td align="center"><b>Dashboard</b><br><img src="project_images/2.jpeg" width="180"/></td>
      <td align="center"><b>Profile</b><br><img src="project_images/3.jpeg" width="180"/></td>
      <td align="center"><b>Health Stats</b><br><img src="project_images/4.jpeg" width="180"/></td>
    </tr>
    <tr>
      <td align="center"><b>Heart Rate</b><br><img src="project_images/5.jpeg" width="180"/></td>
      <td align="center"><b>AI Assistant</b><br><img src="project_images/6.jpeg" width="180"/></td>
      <td align="center"><b>Reminders</b><br><img src="project_images/7.jpeg" width="180"/></td>
    </tr>
    <tr>
      <td align="center"><b>Reports</b><br><img src="project_images/8.jpeg" width="180"/></td>
      <td align="center"><b>Charts</b><br><img src="project_images/9.jpeg" width="180"/></td>
      <td align="center"><b>Settings</b><br><img src="project_images/10.jpeg" width="180"/></td>
    </tr>
    <tr>
      <td align="center"><b>Notifications</b><br><img src="project_images/11.jpeg" width="180"/></td>
      <td align="center"><b>PDF Export</b><br><img src="project_images/12.jpeg" width="180"/></td>
      <td align="center"><b>Data Sync</b><br><img src="project_images/13.jpeg" width="180"/></td>
    </tr>
    <tr>
      <td align="center"><b>History</b><br><img src="project_images/14.jpeg" width="180"/></td>
      <td align="center"><b>Goals</b><br><img src="project_images/15.jpeg" width="180"/></td>
      <td align="center"><b>Trends</b><br><img src="project_images/17.jpeg" width="180"/></td>
    </tr>
    <tr>
      <td align="center"><b>Progress</b><br><img src="project_images/18.jpeg" width="180"/></td>
      <td align="center"><b>Tips</b><br><img src="project_images/19.jpeg" width="180"/></td>
      <td align="center"><b>More</b><br><img src="project_images/20.jpeg" width="180"/></td>
    </tr>
  </table>
</div>


<p align="center">Each screenshot above represents a real screen from the app, giving you a complete visual overview of the Health Monitoring App's user interface.</p>


---

## Technology Stack

- Flutter (3.x)
- Firebase (Auth, Firestore)
- Google Sign-In
- Gemini AI API
- Provider (State Management)
- Shared Preferences
- Camera, Image Picker
- Local Notifications
- Charts: fl_chart, syncfusion_flutter_charts
- PDF: pdf

---

## Getting Started

1. Clone the repository:
  ```bash
  git clone https://github.com/SUNILNAGRKOTI/Health_Monitoring_App.git
  cd Health_Monitoring_App
  ```
2. Install dependencies:
  ```bash
  flutter pub get
  ```
3. Add your Firebase configuration:
  - Place your `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) in the respective folders.
4. Set up your Gemini API key securely:
  - Do not hardcode your API key in the code.
  - Run or build the app with:
    ```bash
    flutter run --dart-define=GROQ_API_KEY=your_key_here
    flutter build apk --dart-define=GROQ_API_KEY=your_key_here
    ```
5. Run the app:
  ```bash
  flutter run
  ```

---

## Credits

- Developed by Sunil Nagarkoti
- Special thanks to the Flutter & Firebase community

---

## Contact

For queries or feedback, email: sunilsinghnagarkoti108@gmail.com
