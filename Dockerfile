FROM python:3.11-slim

# Create dedicated non-root user
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

WORKDIR /app

#Leverage caching for dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

#Copy source code and assign ownership to non-root user
COPY . .
RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]

