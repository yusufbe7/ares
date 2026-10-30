import json, struct, numpy as np
CT = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}
class GLB:
    def __init__(s, path):
        s.b = open(path, 'rb').read()
        l = struct.unpack('<I', s.b[12:16])[0]
        s.j = json.loads(s.b[20:20 + l]); s.bin0 = 20 + l + 8
    def acc(s, i):
        a = s.j['accessors'][i]; bv = s.j['bufferViews'][a['bufferView']]
        off = s.bin0 + bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        n = a['count'] * NC[a['type']]
        arr = np.frombuffer(s.b, dtype=CT[a['componentType']], count=n, offset=off)
        return arr.reshape(a['count'], NC[a['type']]) if NC[a['type']] > 1 else arr
