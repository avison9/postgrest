FROM python:3.9-slim
WORKDIR /app
COPY mapper.py .
COPY requirements.txt .
# RUN pip install fastapi uvicorn httpx boto3 asyncpg aiohttp
RUN pip install --no-cache-dir -r requirements.txt
CMD ["uvicorn", "mapper:app", "--host", "0.0.0.0", "--port", "8000"]