package dev.crafting.guacamole;

import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.UnsupportedEncodingException;
import java.net.URLEncoder;
import java.util.Map;
import java.util.Properties;

import org.apache.guacamole.protocol.GuacamoleConfiguration;

public class Parameters {
    private static String configFile;
    static {
        configFile = System.getenv("GUACAMOLE_PARAMETERS_FILE");
        if (configFile == null || configFile.isEmpty()) {
            configFile = "/etc/guacamole/parameters.properties";
        }
    }

    // The protocol for guacd to connect.
    public String protocol;

    // The hostname of the remote server that guacd should connect.
    public String hostname;

    // The username for authentication.
    public String username;

    // The password for authentication.
    public String password;

    private static Parameters _shared = new Parameters();

    private Parameters() {
        Properties properties = new Properties();
        try (FileInputStream fis = new FileInputStream(Parameters.configFile);) {
            properties.load(fis);
        } catch (IOException e) {
            System.err.println(e.getMessage());
        }
        protocol = properties.getProperty("protocol", "rdp");
        hostname = properties.getProperty("hostname", "localhost");
        username = properties.getProperty("username");
        password = properties.getProperty("password");
    }

    private Parameters(Parameters from) {
        protocol = from.protocol;
        hostname = from.hostname;
        username = from.username;
        password = from.password;
    }

    public static Parameters replica() {
        synchronized (Parameters.class) {
            return new Parameters(_shared);
        }
    }

    public static void update(Map<String, String> params) {
        synchronized (Parameters.class) {
            _shared.protocol = paramNotEmpty(params, "protocol", _shared.protocol);
            _shared.hostname = paramNotEmpty(params, "hostname", _shared.hostname);
            _shared.username = paramEmptyAsNull(params, "username", _shared.username);
            _shared.password = paramEmptyAsNull(params, "password", _shared.password);

            try (FileOutputStream fos = new FileOutputStream(Parameters.configFile)) {
                Properties properties = new Properties();
                properties.setProperty("protocol", _shared.protocol);
                properties.setProperty("hostname", _shared.hostname);
                properties.setProperty("username", _shared.username);
                properties.setProperty("password", _shared.password);
                properties.store(fos, "RDP parameters");
            } catch (IOException e) {
                System.err.println(e.getMessage());
            }
        }
    }

    private static String paramNotEmpty(Map<String, String> params, String key, String defaultValue) {
        String value = params.getOrDefault(key, defaultValue);
        if (value != null && value.isEmpty()) {
            return defaultValue;
        }
        return value;
    }

    private static String paramEmptyAsNull(Map<String, String> params, String key, String defaultValue) {
        String value = params.getOrDefault(key, defaultValue);
        if (value != null && value.isEmpty()) {
            return null;
        }
        return value;
    }

    public void apply(GuacamoleConfiguration config) {
        config.setProtocol(protocol);
        config.setParameter("hostname", hostname);
        if (username != null) {
            config.setParameter("username", username);
        }
        if (password != null) {
            config.setParameter("password", password);
        }
    }

    public String formData() throws UnsupportedEncodingException {
        StringBuilder result = new StringBuilder();
        result.append("protocol=");
        result.append(URLEncoder.encode(protocol, "UTF-8"));
        result.append("&hostname=");
        result.append(URLEncoder.encode(hostname, "UTF-8"));
        if (username != null) {
            result.append("&username=");
            result.append(URLEncoder.encode(username, "UTF-8"));
        }
        if (password != null) {
            result.append("&password=");
            result.append(URLEncoder.encode("*", "UTF-8"));
        }
        return result.toString();
    }
}
