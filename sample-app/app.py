from flask import Flask, jsonify, request
import logging
import time
import random
from prometheus_client import Counter, Histogram, generate_latest, CollectorRegistry, CONTENT_TYPE_LATEST
from prometheus_client import multiprocess, make_wsgi_app
from pythonjsonlogger import jsonlogger
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
import os

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)

# structured logging
logger = logging.getLogger()
logHandler = logging.StreamHandler()
formatter = jsonlogger.JsonFormatter('%(asctime)s %(levelname)s %(name)s %(message)s')
logHandler.setFormatter(formatter)
logger.addHandler(logHandler)
logger.setLevel(logging.INFO)

# Prometheus metrics (use conventional metric names and labels for easier querying)
REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['job', 'code', 'path'])
REQUEST_LATENCY = Histogram('http_request_latency_seconds', 'Request latency', ['job', 'path'])

# Tracing
resource = Resource(attributes={"service.name": "sample-app"})
provider = TracerProvider(resource=resource)
otlp_endpoint = os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT', 'lgtm-tempo.lgtm.svc.cluster.local:4317')
span_exporter = OTLPSpanExporter(endpoint=otlp_endpoint, insecure=True)
provider.add_span_processor(BatchSpanProcessor(span_exporter))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

@app.route('/metrics')
def metrics():
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@app.route('/health')
def health():
    return jsonify({'status':'ok'}), 200

@app.route('/work')
def work():
    start = time.time()
    # simulate work and occasional latency injection
    delay = random.choice([0.05, 0.1, 0.2, 0.5, 1.5])
    time.sleep(delay)
    duration = time.time() - start
    # increment metrics with labels
    REQUEST_COUNT.labels(job='sample-app', code='200', path=request.path).inc()
    REQUEST_LATENCY.labels(job='sample-app', path=request.path).observe(duration)
    with tracer.start_as_current_span('work-handler'):
        logger.info('request_processed', extra={'path': request.path, 'duration': delay, 'status': 200})
    return jsonify({'status':'done', 'delay': delay}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
