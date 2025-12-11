package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

type HealthResponse struct {
	Status    string    `json:"status"`
	Timestamp time.Time `json:"timestamp"`
	Version   string    `json:"version"`
	Compute   string    `json:"compute"`
}

type MessageResponse struct {
	Message   string            `json:"message"`
	Path      string            `json:"path"`
	Method    string            `json:"method"`
	Headers   map[string]string `json:"headers"`
	Timestamp time.Time         `json:"timestamp"`
}

type ErrorResponse struct {
	Error     string    `json:"error"`
	Timestamp time.Time `json:"timestamp"`
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	compute := os.Getenv("COMPUTE_TYPE")
	if compute == "" {
		compute = "local"
	}

	response := HealthResponse{
		Status:    "healthy",
		Timestamp: time.Now(),
		Version:   "1.0.0",
		Compute:   compute,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func apiHandler(w http.ResponseWriter, r *http.Request) {
	headers := make(map[string]string)
	for name, values := range r.Header {
		if len(values) > 0 {
			headers[name] = values[0]
		}
	}

	response := MessageResponse{
		Message:   "Hello from Serverless Containers with Go!",
		Path:      r.URL.Path,
		Method:    r.Method,
		Headers:   headers,
		Timestamp: time.Now(),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func userHandler(w http.ResponseWriter, r *http.Request) {
	type User struct {
		ID        int       `json:"id"`
		Name      string    `json:"name"`
		Email     string    `json:"email"`
		CreatedAt time.Time `json:"created_at"`
	}

	users := []User{
		{ID: 1, Name: "Mo", Email: "mo@example.com", CreatedAt: time.Now().Add(-24 * time.Hour)},
		{ID: 2, Name: "Alice", Email: "alice@example.com", CreatedAt: time.Now().Add(-48 * time.Hour)},
		{ID: 3, Name: "Bob", Email: "bob@example.com", CreatedAt: time.Now().Add(-72 * time.Hour)},
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(users)
}

func notFoundHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusNotFound)

	response := ErrorResponse{
		Error:     fmt.Sprintf("Route not found: %s %s", r.Method, r.URL.Path),
		Timestamp: time.Now(),
	}

	json.NewEncoder(w).Encode(response)
}

func loggingMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		log.Printf("Started %s %s", r.Method, r.URL.Path)
		next(w, r)
		log.Printf("Completed %s %s in %v", r.Method, r.URL.Path, time.Since(start))
	}
}

func main() {
	mux := http.NewServeMux()

	mux.HandleFunc("/health", loggingMiddleware(healthHandler))
	mux.HandleFunc("/api/hello", loggingMiddleware(apiHandler))
	mux.HandleFunc("/api/users", loggingMiddleware(userHandler))
	mux.HandleFunc("/", loggingMiddleware(notFoundHandler))

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Starting server on port %s", port)
	log.Printf("Health check: http://localhost:%s/health", port)
	log.Printf("API endpoints: http://localhost:%s/api/hello, http://localhost:%s/api/users", port, port)

	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatal(err)
	}
}
