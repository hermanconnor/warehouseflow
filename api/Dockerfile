FROM python:3.12-slim

# Prevent Python from writing .pyc files and force unbuffered logging for real-time Docker logs
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# 1. Copy requirements from root context and install
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# 2. Copy the entire repository into the container workspace
COPY . .

EXPOSE 8000

# 3. Target the core application utilizing the full package namespace layout
CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]