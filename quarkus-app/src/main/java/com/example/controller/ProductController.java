package com.example.controller;

import com.example.model.Product;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.List;

@Path("/api/products")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class ProductController {

    @GET
    public List<Product> getAllProducts() {
        return Product.listAll();
    }

    @POST
    @Transactional
    public Response createProduct(Product product) {
        product.persist();
        return Response.status(Response.Status.CREATED).entity(product).build();
    }

    @GET
    @Path("/{id}")
    public Response getProductById(@PathParam("id") Long id) {
        Product product = Product.findById(id);
        if (product == null) {
            return Response.status(Response.Status.NOT_FOUND).build();
        }
        return Response.ok(product).build();
    }

    @DELETE
    @Path("/{id}")
    @Transactional
    public Response deleteProduct(@PathParam("id") Long id) {
        boolean deleted = Product.deleteById(id);
        if (!deleted) {
            return Response.status(Response.Status.NOT_FOUND).build();
        }
        return Response.noContent().build();
    }

    @PUT
    @Path("/{id}")
    @Transactional
    public Response updateProduct(@PathParam("id") Long id, Product updatedData) {
        Product product = Product.findById(id);
        if (product == null) {
            return Response.status(Response.Status.NOT_FOUND).build();
        }

        product.name = updatedData.name;
        product.price = updatedData.price;

        return Response.ok(product).build();
    }
}