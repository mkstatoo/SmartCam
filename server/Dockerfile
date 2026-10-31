FROM python:3.12-slim
WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app ./app
ENV DC_DB_PATH=/data/detective.db
VOLUME /data
EXPOSE 8000
# پشت Nginx/Caddy با HTTPS اجرا شود؛ --proxy-headers برای IP واقعی کاربر
CMD ["uvicorn", "app.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
