from fastapi import FastAPI
from fastapi.responses import HTMLResponse
import datetime
import socket

app = FastAPI()

@app.get("/")
def home():
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    hostname = socket.gethostname()
    html_content = f"""
    <html>
        <head><title>CCM Engine Live</title><style>body {{ font-family: sans-serif; background-color: #1e1e2e; color: #cdd6f4; text-align: center; padding: 50px; }} .container {{ background: #313244; padding: 30px; border-radius: 10px; box-shadow: 0px 4px 10px rgba(0,0,0,0.5); display: inline-block; border: 1px solid #89b4fa; }} h1 {{ color: #89b4fa; }} .data {{ font-size: 1.2em; margin: 10px 0; }} .highlight {{ color: #f38ba8; font-weight: bold; }}</style></head>
        <body><div class="container"><h1>🚀 Project CCM is LIVE</h1><p class="data">Server Time: <span class="highlight">{now}</span></p><p class="data">Container ID: <span class="highlight">{hostname}</span></p></div></body>
    </html>
    """
    return HTMLResponse(content=html_content, status_code=200)

@app.get("/health")
def health():
    return {"status": "healthy", "service": "ccm-ec2-live"}