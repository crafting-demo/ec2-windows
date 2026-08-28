package dev.crafting.guacamole;

import java.util.Map;
import java.util.HashMap;

import javax.servlet.ServletException;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.io.PrintWriter;

public class ParamsServlet extends HttpServlet {
    protected void doGet(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        replyWithParams(response);
    }

    protected void doPut(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        Map<String, String> params = new HashMap<>();
        for (Map.Entry<String, String[]> entry : request.getParameterMap().entrySet()) {
            String[] values = entry.getValue();
            if (values != null && values.length > 0) {
                params.put(entry.getKey(), values[0]);
            }
        }
        Parameters.update(params);
        replyWithParams(response);
    }

    private void replyWithParams(HttpServletResponse response) throws IOException {
        response.setContentType("application/x-www-form-urlencoded");
        response.setCharacterEncoding("utf-8");
        PrintWriter out = response.getWriter();
        out.println(Parameters.replica().formData());
        out.close();
    }
}