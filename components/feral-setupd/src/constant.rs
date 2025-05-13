use uuid::Uuid;

// BLuetooth configuration
pub const SERVICE_UUID: Uuid = Uuid::from_u128(0xf7826da64fa24e988024bc5b71e0893e_u128);
pub const CMD_CHAR_UUID: Uuid = Uuid::from_u128(0x6e400002b5a3f393e0a9e50e24dcca9e_u128);
// pub const CMD_CHAR_UUID: Uuid = Uuid::from_u128(0x6e400003b5a3f393e0a9e50e24dcca9e_u128);
// pub const ENG_CHAR_UUID: Uuid = Uuid::parse_str("6e400004-b5a3-f393-e0a9-e50e24dcca9e").unwrap();
pub const CMD_CONNECT_WIFI: &str = "connect_wifi";
pub const CMD_SCAN_WIFI: &str = "scan_wifi";
pub const CMD_GET_INFO: &str = "get_info";
pub const MAX_SSIDS: usize = 9;
pub const MD5_LENGTH: usize = 8; // Used for conversion to device ID
pub const DEVICE_ID_PREFIX: &str = "FF-X1-";

// Chrome
pub const CDP_URL: &str = "http://127.0.0.1:9222/json";
pub const DAILY_URL: &str =
    "https://support-feralfile-device.feralfile-display-prod.pages.dev?platform=ff-device";
pub const QRCODE_URL_PREFIX: &str = "/opt/feral/ui/launcher/index.html?step=qr&device_id=";

pub const CACHE_FILEPATH: &str = "/home/feralfile/.state/setupd";

pub const DBUS_SETUPD_OBJECT: &str = "/com/feralfile/setupd";
pub const DBUS_CONNECTD_OBJECT: &str = "/com/feralfile/connectd";

pub const DBUS_SETUPD_INTERFACE: &str = "com.feralfile.setupd.general";
pub const DBUS_CONNECTD_INTERFACE: &str = "com.feralfile.connectd.general";

pub const DBUS_EVENT_WIFI_CONNECTED: &str = "wifi_connected";
pub const DBUS_EVENT_RELAYER_CONFIGURED: &str = "relayer_configured";

pub const DBUS_CONNECTD_TIMEOUT: u64 = 60 * 1000 * 1000; // 60 seconds
