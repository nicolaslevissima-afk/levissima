# Cifra um segredo para o GitHub Actions (crypto_box_seal do libsodium, como a API do GitHub exige).
import base64, ctypes, sys
L = ctypes.CDLL('libsodium.so.23')
assert L.sodium_init() >= 0
SEAL = L.crypto_box_sealbytes()
def selar(chave_pub_b64, valor):
    pk = base64.b64decode(chave_pub_b64)
    msg = valor.encode() if isinstance(valor, str) else valor
    out = ctypes.create_string_buffer(len(msg) + SEAL)
    assert L.crypto_box_seal(out, msg, ctypes.c_ulonglong(len(msg)), pk) == 0
    return base64.b64encode(out.raw).decode()
def teste():
    pk = ctypes.create_string_buffer(32); sk = ctypes.create_string_buffer(32)
    L.crypto_box_keypair(pk, sk)
    c = base64.b64decode(selar(base64.b64encode(pk.raw), 'segredo-de-teste'))
    m = ctypes.create_string_buffer(len(c) - SEAL)
    assert L.crypto_box_seal_open(m, c, ctypes.c_ulonglong(len(c)), pk, sk) == 0
    assert m.raw == b'segredo-de-teste'
    print('selar ok')
if __name__ == '__main__':
    teste()
