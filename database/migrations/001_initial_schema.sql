-- GalleryOnTheGo — Initial Database Schema
-- Tables: devices, settings
-- No user table — admin uses predefined env credentials

-- ─── Devices ───
-- Auto-registered when Android app connects
CREATE TABLE IF NOT EXISTS devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_name VARCHAR(100) NOT NULL,
    device_model VARCHAR(100),
    android_version VARCHAR(20),
    device_token TEXT UNIQUE NOT NULL,
    fcm_token TEXT,
    is_active BOOLEAN DEFAULT true,
    last_seen_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Index for quick lookups by token
CREATE INDEX idx_devices_device_token ON devices(device_token);
CREATE INDEX idx_devices_is_active ON devices(is_active);

-- ─── Settings ───
-- Global admin settings (single row)
CREATE TABLE IF NOT EXISTS settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    theme VARCHAR(20) DEFAULT 'dark',
    grid_columns INTEGER DEFAULT 4,
    auto_reconnect BOOLEAN DEFAULT true,
    notifications_enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Insert default settings row
INSERT INTO settings (theme, grid_columns, auto_reconnect, notifications_enabled)
VALUES ('dark', 4, true, true);

-- ─── Updated At Trigger ───
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_devices_updated_at
    BEFORE UPDATE ON devices
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_settings_updated_at
    BEFORE UPDATE ON settings
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
