FROM python:3.10-slim AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copy requirements file
COPY requirements.txt .

# Install dependencies into a virtual environment
RUN python -m venv /venv
ENV PATH="/venv/bin:$PATH"
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Final stage
FROM python:3.10-slim

# Copy virtual environment from builder stage
COPY --from=builder /venv /venv
ENV PATH="/venv/bin:$PATH"

WORKDIR /app

# Copy application code and patch script
COPY streamlitui.py .
COPY fix-secrets.py .

# Apply the fix to handle the API keys properly
RUN python fix-secrets.py && \
    rm fix-secrets.py

# Create directory for pod role info
RUN mkdir -p /etc/podinfo

# Expose Streamlit port
EXPOSE 8501

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Healthcheck
HEALTHCHECK --interval=5s --timeout=3s --retries=3 CMD curl -f http://localhost:8501/_stcore/health || exit 1

# Run Streamlit app with better error reporting
ENTRYPOINT ["streamlit", "run", "streamlitui.py", "--server.port=8501", "--server.address=0.0.0.0", "--logger.level=info"] 