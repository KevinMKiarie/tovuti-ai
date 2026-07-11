FROM python:3.12-slim

RUN apt-get update && apt-get install -y ffmpeg espeak-ng build-essential && rm -rf /var/lib/apt/lists/*

WORKDIR /service

# Install PyTorch before copying requirements.txt so this heavy layer stays
# cached when other dependencies change.
RUN pip install --no-cache-dir \
    "torch==2.6.0+cpu" "torchaudio==2.6.0+cpu" \
    --extra-index-url https://download.pytorch.org/whl/cpu

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt \
    --extra-index-url https://download.pytorch.org/whl/cpu

COPY . .

RUN python generate_templates.py

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
