FROM python:3.9-slim
WORKDIR /app
COPY mapper.py .
RUN pip install fastapi uvicorn httpx boto3
CMD ["uvicorn", "mapper:app", "--host", "0.0.0.0", "--port", "8000"]