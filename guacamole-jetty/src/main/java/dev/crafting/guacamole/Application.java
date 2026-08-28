package dev.crafting.guacamole;

public class Application {
    public static void main(String[] args) throws Exception
    {
        TunnelServer tunnelServer = new TunnelServer();
        tunnelServer.start();
        ConfigServer configServer = new ConfigServer();
        configServer.start();
        tunnelServer.join();
        configServer.join();
    }
}
