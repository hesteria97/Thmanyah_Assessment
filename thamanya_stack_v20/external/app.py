from flask import Flask, request, jsonify
app = Flask(__name__)
@app.route("/events", methods=["POST"])
def events():
    data = request.get_json(force=True, silent=True) or {}
    print("[external-api] got event:", data, flush=True)
    return jsonify({"ok": True, "received": bool(data)})
@app.route("/", methods=["GET"])
def index():
    return "OK", 200
