import os
import re

import gradio as gr
from huggingface_hub import InferenceClient
from transformers import pipeline

# ---- Two most important lines in the whole assignment ----
LOCAL_MODEL = "Qwen/Qwen3-0.6B"          # small enough to run on free CPU Space
REMOTE_MODEL = "openai/gpt-oss-20b"      # bigger model, called via API

# Loaded once at startup, regardless of the checkbox.
pipe = pipeline("text-generation", model=LOCAL_MODEL)


def clean_token(raw):
    """Strip whitespace and stray quote characters that sneak in from the shell."""
    if not raw:
        return None
    return raw.strip().strip('"').strip("'").strip()


# Startup diagnostic - prints to your terminal, not the browser.
_env_token = clean_token(os.environ.get("HF_TOKEN"))
if _env_token:
    print(
        f"HF_TOKEN found: length={len(_env_token)}, starts_with_hf_={_env_token.startswith('hf_')}")
else:
    print("HF_TOKEN not set - remote model will rely on the login button.")


def local_generate(messages, max_tokens, temperature, top_p):
    outputs = pipe(
        messages,
        max_new_tokens=max_tokens,
        do_sample=True,
        temperature=temperature,
        top_p=top_p,
    )
    text = outputs[0]["generated_text"][-1]["content"]
    # Qwen3 is a reasoning model and emits a scratchpad before the answer.
    return re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL).strip()


def respond(
    message,
    history,
    system_message,
    max_tokens,
    temperature,
    top_p,
    use_local_model,
    hf_token: gr.OAuthToken | None,
):
    messages = [{"role": "system", "content": system_message}]
    messages.extend(history)
    messages.append({"role": "user", "content": message})

    # ---- Branch 1: run the small model on this machine ----
    if use_local_model:
        try:
            yield local_generate(messages, max_tokens, temperature, top_p)
        except Exception as e:
            yield f"❌ Local model failed:\n\n`{type(e).__name__}: {e}`"
        return

    # ---- Branch 2: call the big model over the Inference API ----
    token = clean_token(os.environ.get("HF_TOKEN"))
    if not token and hf_token is not None:
        token = clean_token(hf_token.token)

    if not token:
        yield (
            "⚠️ No token found. Log in with the button above, "
            'or set $env:HF_TOKEN="hf_..." before running locally.'
        )
        return

    if not token.startswith("hf_"):
        yield (
            "⚠️ The token doesn't start with `hf_`, so the Hugging Face router "
            "will reject it. Check for stray quotes or whitespace in your "
            "`$env:HF_TOKEN` value and set it again."
        )
        return

    try:
        client = InferenceClient(token=token, model=REMOTE_MODEL)
        response = ""
        for chunk in client.chat_completion(
            messages,
            max_tokens=max_tokens,
            stream=True,
            temperature=temperature,
            top_p=top_p,
        ):
            choices = chunk.choices
            if len(choices) and choices[0].delta.content:
                response += choices[0].delta.content
                yield response

        if not response:
            yield "⚠️ The remote model returned an empty response."

    except Exception as e:
        yield f"❌ Remote model failed:\n\n`{type(e).__name__}: {e}`"


with gr.Blocks() as demo:
    with gr.Row():
        gr.Markdown("<h1 style='text-align: center;'>💬 My Chatbot</h1>")
        gr.LoginButton()

    gr.ChatInterface(
        fn=respond,
        additional_inputs=[
            gr.Textbox(value="You are a friendly Chatbot.",
                       label="System message"),
            gr.Slider(minimum=1, maximum=2048, value=512,
                      step=1, label="Max new tokens"),
            gr.Slider(minimum=0.1, maximum=2.0, value=0.7,
                      step=0.1, label="Temperature"),
            gr.Slider(minimum=0.1, maximum=1.0, value=0.95,
                      step=0.05, label="Top-p (nucleus sampling)"),
            gr.Checkbox(label="Use Local Model", value=False),
        ],
    )

    gr.Markdown(
        "Use **Additional inputs** to switch between the API model and the locally executed model."
    )

if __name__ == "__main__":
    demo.launch()
