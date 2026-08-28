package dev.crafting.guacamole;

import org.eclipse.jetty.server.Server;
import org.eclipse.jetty.server.ServerConnector;
import org.eclipse.jetty.servlet.ServletContextHandler;

public class ConfigServer {

    private final Server server = new Server();
    private final ServerConnector connector = new ServerConnector(server);

    public ConfigServer() {
        connector.setPort(8081);
        server.addConnector(connector);

        ServletContextHandler context = new ServletContextHandler(server, "/");
        context.addServlet(ParamsServlet.class, "/params");
    }

    public void start() throws Exception {
        server.start();
    }
    
    public void join() throws InterruptedException {
        server.join();
    }
}
