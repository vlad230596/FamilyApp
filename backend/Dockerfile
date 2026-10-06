FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 POETRY_VIRTUALENVS_CREATE=false
WORKDIR /app
RUN pip install --no-cache-dir poetry==2.3.4
COPY pyproject.toml poetry.lock ./
RUN poetry install --only main --no-root --no-interaction
COPY familyapp ./familyapp
RUN useradd --uid 10001 --create-home familyapp && mkdir -p /app/instance /data && chown -R familyapp:familyapp /app/instance /data
USER familyapp
EXPOSE 8000
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "1", "--threads", "4", "familyapp:create_app()"]
