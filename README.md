---
title: StudyMate AI
emoji: 🎓
colorFrom: yellow
colorTo: purple
sdk: gradio
sdk_version: "6.5.1"
app_file: app.py
pinned: false
hf_oauth: true
hf_oauth_scopes:
  - inference-api
short_description: AI study assistant with remote and local LLMs
---

# StudyMate AI

An AI study assistant built with Gradio for DS/CS 553 Case Study 1. It can answer
questions with a remotely hosted LLM (Qwen3-32B through Hugging Face Inference) or
a model running locally on the Space (Qwen3-0.6B).

Check out the configuration reference at https://huggingface.co/docs/hub/spaces-config-reference