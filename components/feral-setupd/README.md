# Flow

- Startup

  - Has topic id & location id cache => show daily
  - Don't have topic id & location cache =>
    - Broadcast bluetooth
    - Show QRCode
    - Setup wifi
    - Receive topic id & location id
    - Send to mobile + navigate to daily

- While running
  - Request to connect second device (from connectd)
    - Broadcast bluetooth
    - Show QRCode
    - Send topic id & location id cache to mobile
    - Show daily
  - Request to show daily (from connectd)
    - Show daily
