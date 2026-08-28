package dev.crafting.guacamole;

import java.util.Arrays;
import java.util.List;

import javax.websocket.EndpointConfig;
import javax.websocket.Session;
import org.apache.guacamole.GuacamoleException;
import org.apache.guacamole.net.GuacamoleTunnel;
import org.apache.guacamole.net.GuacamoleSocket;
import org.apache.guacamole.net.InetGuacamoleSocket;
import org.apache.guacamole.net.SimpleGuacamoleTunnel;
import org.apache.guacamole.protocol.ConfiguredGuacamoleSocket;
import org.apache.guacamole.protocol.GuacamoleConfiguration;
import org.apache.guacamole.websocket.GuacamoleWebSocketTunnelEndpoint;

public class WebsocketTunnel extends GuacamoleWebSocketTunnelEndpoint {
    private static String guacdHost = "localhost";
    private static int guacdPort = 4822;

    static {
        String value = System.getenv("GUACD_PORT");
        if (value != null) {
            try {
                int port = Integer.parseInt(value);
                if (port > 0) {
                    guacdPort = port;
                }
            } catch (NumberFormatException e) {
                // Ignore.
            }
        }
        value = System.getenv("GUACD_HOST");
        if (value != null) {
            guacdHost = value;
        }
    }

    @Override
    protected GuacamoleTunnel createTunnel(Session session,
            EndpointConfig endpointConfig) throws GuacamoleException {
        GuacamoleConfiguration config = new GuacamoleConfiguration();
        Parameters.replica().apply(config);
        config.setParameter("ignore-cert", "true");
        config.setParameter("resize-method", "display-update");
        config.setParameter("enable-font-smoothing", "true");
        config.setParameter("force-lossless", "true");
        // Get other params from URL query. The query is null when the endpoint
        // is opened without one, which guacd tolerates by falling back to its
        // default display size, so this must not be treated as an error.
        List<String> allowedParams = Arrays.asList("width", "height");
        String queryString = session.getRequestURI().getQuery();
        if (queryString != null) {
            for (String param : queryString.split("&")) {
                String[] parts = param.split("=");
                if (parts.length == 2 && allowedParams.contains(parts[0])) {
                    config.setParameter(parts[0], parts[1]);
                }
            }
        }

        // Connect to guacd - everything is hard-coded here.
        GuacamoleSocket socket = new ConfiguredGuacamoleSocket(
                new InetGuacamoleSocket(guacdHost, guacdPort),
                config);

        return new SimpleGuacamoleTunnel(socket);
    }
}