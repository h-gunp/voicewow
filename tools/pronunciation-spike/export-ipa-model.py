"""Export a small ONNX graph referencing the original pinned safetensors file.

Run with an isolated environment containing torch==2.15.0+cpu,
transformers==4.57.6 and onnx==1.23.2:
  python export-ipa-model.py --source-dir PATH_TO_UPSTREAM_SNAPSHOT

The source directory must contain model.safetensors and the original config.json.
This script never uploads, publishes, quantizes, or redistributes weights. The
result references model.safetensors by relative path; deployments obtain that
file from the pinned upstream URL recorded in the provenance manifest.
No license grant is inferred from a public download URL.
"""
import argparse
import hashlib
import json
import mmap
from pathlib import Path
import struct
import tempfile

import numpy as np
import onnx
from onnx import TensorProto, numpy_helper
import torch
import transformers
from transformers import Wav2Vec2ForCTC

REPOSITORY = 'icig/normal-korean-ipa-translation'
REVISION = '772950d64427910937e11c5b76c9e4594059ce8c'
WEIGHT_BYTES = 377681876
WEIGHT_SHA256 = 'dfe465932554b8d8d5ff818afb27995fc7ac20e6af7e3b77f26a8aa7e7dc0404'
EXPECTED_GRAPH_SHA256 = '840b1a2f19d1b2c52ac5ef522764d5e5fb42ad79a0b839805904ed1b6b36f949'
LARGE_STATIC_CONSTANTS = {
    '/model/wav2vec2/feature_extractor/conv_layers.0/layer_norm/Constant_1': 1.0,
    '/model/wav2vec2/feature_extractor/conv_layers.0/layer_norm/Constant_2': 0.0,
}


def sha256(path):
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


class Logits(torch.nn.Module):
    def __init__(self, source):
        super().__init__()
        self.model = source

    def forward(self, input_values):
        return self.model(input_values).logits


def externalize(graph, weight):
    matched = []
    with weight.open('rb') as source, mmap.mmap(source.fileno(), 0, access=mmap.ACCESS_READ) as raw:
        header_length = struct.unpack('<Q', raw[:8])[0]
        header = json.loads(raw[8:8 + header_length])
        by_signature = {}
        for name, spec in header.items():
            if name == '__metadata__':
                continue
            if spec['dtype'] != 'F32':
                raise ValueError(f'Unexpected source dtype: {name}')
            begin, end = spec['data_offsets']
            offset, length = 8 + header_length + begin, end - begin
            data = raw[offset:offset + length]
            if len(data) != length:
                raise ValueError(f'Invalid source bounds: {name}')
            signature = (tuple(spec['shape']), hashlib.sha256(data).hexdigest())
            by_signature.setdefault(signature, []).append((name, offset, length))
        for tensor in graph.graph.initializer:
            data = numpy_helper.to_array(tensor).tobytes()
            signature = (tuple(tensor.dims), hashlib.sha256(data).hexdigest())
            matches = by_signature.get(signature, []) if tensor.data_type == TensorProto.FLOAT else []
            if not matches:
                raise ValueError(f'Initializer has no exact upstream bytes: {tensor.name}')
            name, offset, length = next((m for m in matches if tensor.name.endswith(m[0])), matches[0])
            if data != raw[offset:offset + length]:
                raise ValueError(f'Byte comparison failed: {tensor.name}')
            matched.append({'name': tensor.name, 'source_tensor': name, 'offset': offset,
                            'length': length, 'sha256': signature[1]})
            tensor.ClearField('raw_data')
            tensor.ClearField('float_data')
            tensor.data_location = TensorProto.EXTERNAL
            del tensor.external_data[:]
            for key, value in {'location': 'model.safetensors', 'offset': str(offset), 'length': str(length)}.items():
                entry = tensor.external_data.add()
                entry.key, entry.value = key, value
    constants = []
    for node in graph.graph.node:
        for attribute in node.attribute:
            if attribute.type == onnx.AttributeProto.GRAPH or attribute.type == onnx.AttributeProto.GRAPHS:
                raise ValueError('Unexpected nested graph requires a separate weight audit')
            if attribute.type != onnx.AttributeProto.TENSOR:
                continue
            data = numpy_helper.to_array(attribute.t)
            if data.nbytes > 1024:
                expected = LARGE_STATIC_CONSTANTS.get(node.name)
                if expected is None or data.shape != (512,) or not np.all(data == expected):
                    raise ValueError(f'Unexpected large embedded constant: {node.name}')
            constants.append({'node': node.name, 'shape': list(data.shape), 'dtype': str(data.dtype),
                              'bytes': data.nbytes, 'sha256': hashlib.sha256(data.tobytes()).hexdigest()})
    if len(matched) != 212 or any(t.raw_data or t.float_data for t in graph.graph.initializer):
        raise ValueError('Unexpected initializer count or remaining embedded values')
    return matched, constants


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    source_dir = args.source_dir.resolve()
    weight = source_dir / 'model.safetensors'
    output = args.output or source_dir / 'model.upstream-external.onnx'
    if weight.stat().st_size != WEIGHT_BYTES or sha256(weight) != WEIGHT_SHA256:
        raise ValueError('Pinned upstream safetensors size/SHA256 mismatch')
    torch.set_num_threads(1)
    torch.set_num_interop_threads(1)
    model = Wav2Vec2ForCTC.from_pretrained(source_dir, local_files_only=True,
        trust_remote_code=False, attn_implementation='eager').eval()
    with tempfile.TemporaryDirectory(prefix='voicemate-ipa-export-') as temporary:
        full = Path(temporary) / 'full.onnx'
        torch.onnx.export(Logits(model), (torch.zeros((1, 16000)),), str(full),
            dynamo=False, do_constant_folding=False, opset_version=17,
            input_names=['input_values'], output_names=['logits'],
            dynamic_axes={'input_values': {1: 'samples'}, 'logits': {1: 'frames'}})
        graph = onnx.load(str(full), load_external_data=False)
    matched, constants = externalize(graph, weight)
    serialized = graph.SerializeToString()
    graph_hash = hashlib.sha256(serialized).hexdigest()
    if graph_hash != EXPECTED_GRAPH_SHA256:
        raise ValueError('Export differs from verified graph; review dependency versions and graph before publishing')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(serialized)
    sources = []
    for name in ['model.safetensors', 'config.json', 'preprocessor_config.json', 'vocab.json',
                 'added_tokens.json', 'tokenizer_config.json', 'special_tokens_map.json']:
        path = source_dir / name
        sources.append({'file': name, 'bytes': path.stat().st_size, 'sha256': sha256(path),
                        'url': f'https://huggingface.co/{REPOSITORY}/resolve/{REVISION}/{name}'})
    report = {'repository': REPOSITORY, 'revision': REVISION,
        'license': 'Not specified in upstream metadata or repository files; no grant inferred',
        'sources': sources, 'graph': {'file': output.name, 'bytes': len(serialized), 'sha256': graph_hash,
            'external_location': 'model.safetensors', 'embedded_initializer_bytes': 0},
        'export': {'torch': torch.__version__, 'transformers': transformers.__version__, 'onnx': onnx.__version__,
            'opset': 17, 'dynamo': False, 'do_constant_folding': False, 'attention': 'eager'},
        'preprocessing': {'sampling_rate': 16000, 'channels': 1, 'dtype': 'float32',
            'do_normalize': False, 'return_attention_mask': False},
        'matched_initializers': matched, 'embedded_static_constants': constants,
        'note': 'All 212 learned initializers reference original source bytes. Embedded graph constants describe operators/shapes; two 512-element all-one/all-zero tensors implement InstanceNormalization.'}
    output.with_suffix('.provenance.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report['graph']))


if __name__ == '__main__':
    main()
