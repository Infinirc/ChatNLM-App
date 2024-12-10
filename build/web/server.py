from flask import Flask, send_from_directory, make_response
from flask_compress import Compress
import os

app = Flask(__name__, static_folder='/Users/rickychen/Documents/chatnlm/build/web')
Compress(app)  # 启用 Gzip 压缩

@app.route('/', defaults={'path': ''})
@app.route('/<path:path>')
def serve(path):
    file_path = os.path.join(app.static_folder, path)
    if os.path.isfile(file_path):
        response = make_response(send_from_directory(app.static_folder, path))
        response.headers['Cache-Control'] = 'public, max-age=31536000'  # 缓存 1 年
        return response
    elif path == "":
        return send_from_directory(app.static_folder, 'index.html')
    else:
        return send_from_directory(app.static_folder, 'index.html')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)
