use uuid::Uuid;

pub const SERVICE_UUID: Uuid = Uuid::from_u128(0xf7826da64fa24e988024bc5b71e0893e_u128);
pub const SETUP_CHAR_UUID: Uuid = Uuid::from_u128(0x6e400002b5a3f393e0a9e50e24dcca9e_u128);
// pub const CMD_CHAR_UUID: Uuid = Uuid::from_u128(0x6e400003b5a3f393e0a9e50e24dcca9e_u128);
// pub const ENG_CHAR_UUID: Uuid = Uuid::parse_str("6e400004-b5a3-f393-e0a9-e50e24dcca9e").unwrap();

pub const DBUS_SETUPD_OBJECT: &str = "/com/feralfile/setupd";
pub const DBUS_CONNECTD_OBJECT: &str = "/com/feralfile/connectd";

pub const DBUS_SETUPD_INTERFACE: &str = "com.feralfile.setupd.general";
pub const DBUS_CONNECTD_INTERFACE: &str = "com.feralfile.connectd.general";

pub const DBUS_EVENT_WIFI_CONNECTED: &str = "wifi_connected";
pub const DBUS_EVENT_REPLAYER_CONFIGURED: &str = "relayer_configured";

pub const DBUS_CONNECTD_TIMEOUT: u64 = 60 * 1000 * 1000; // 60 seconds
pub const MAX_SSIDS: usize = 9;
