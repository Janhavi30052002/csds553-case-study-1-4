"""Tests for the local Qwen3-0.6B model.

These run on CPU with float32 so they work on GitHub Actions runners,
which have no GPU.
"""

import pytest
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer

MODEL_ID = "Qwen/Qwen3-0.6B"


@pytest.fixture(scope="module")
def tokenizer():
    """Load the tokenizer once and reuse it across tests."""
    return AutoTokenizer.from_pretrained(MODEL_ID)


@pytest.fixture(scope="module")
def model():
    """Load the model once on CPU in float32 and reuse it across tests."""
    m = AutoModelForCausalLM.from_pretrained(
        MODEL_ID, torch_dtype=torch.float32)
    m.to("cpu")
    m.eval()
    return m


def test_tokenizer_loads(tokenizer):
    """The tokenizer should load and expose a non-empty vocabulary."""
    assert tokenizer is not None
    assert tokenizer.vocab_size > 0


def test_model_loads_on_cpu_float32(model):
    """The model should sit on CPU with float32 weights."""
    param = next(model.parameters())
    assert param.device.type == "cpu"
    assert param.dtype == torch.float32


def test_tokenizer_encodes_and_decodes(tokenizer):
    """Encoding then decoding should return the original text."""
    text = "Hello, world!"
    ids = tokenizer(text)["input_ids"]

    assert isinstance(ids, list)
    assert len(ids) > 0

    decoded = tokenizer.decode(ids, skip_special_tokens=True)
    assert decoded.strip() == text


def test_chat_template_applies(tokenizer):
    """The chat template should turn messages into a prompt string."""
    messages = [{"role": "user", "content": "What is 2 + 2?"}]
    prompt = tokenizer.apply_chat_template(
        messages,
        tokenize=False,
        add_generation_prompt=True,
        enable_thinking=False,
    )

    assert isinstance(prompt, str)
    assert len(prompt) > 0


def test_generation_produces_new_tokens(model, tokenizer):
    """Generation should append tokens and decode to a non-empty reply."""
    messages = [{"role": "user", "content": "Say hello in one word."}]
    prompt = tokenizer.apply_chat_template(
        messages,
        tokenize=False,
        add_generation_prompt=True,
        enable_thinking=False,
    )
    inputs = tokenizer(prompt, return_tensors="pt")

    with torch.no_grad():
        output = model.generate(
            **inputs,
            max_new_tokens=16,
            do_sample=False,
        )

    input_len = inputs["input_ids"].shape[1]
    assert output.shape[1] > input_len

    reply = tokenizer.decode(output[0][input_len:], skip_special_tokens=True)
    assert isinstance(reply, str)
    assert len(reply.strip()) > 0
