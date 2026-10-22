"""Bounded, redacted activity snapshots; inference remains owned by upstream."""
from functools import wraps
from pathlib import Path
from threading import Lock

from .job import atomic_json


class LLMActivity:
    def __init__(self, directory: Path, request_id: str, secrets):
        self.path = directory / 'llm-output.json'
        self.request_id = request_id
        self.secrets = secrets
        self.text = ''
        self.lock = Lock()

    def publish(self, state, text=''):
        with self.lock:
            for secret in self.secrets:
                text = text.replace(secret, '[REDACTED]')
            if text:
                self.text = (self.text + text + '\n\n')[-32000:]
            atomic_json(self.path, {'requestID': self.request_id, 'state': state, 'text': self.text})


def install_llm_activity(requester_type, activity):
    original = requester_type.request_chat_completion

    @wraps(original)
    def request(self, profile, api_args, *args, **kwargs):
        activity.publish('requesting')
        try:
            result = original(self, profile, api_args, *args, **kwargs)
        except Exception:
            activity.publish('failed')
            raise
        activity.publish('received', str(getattr(result, 'content', '') or ''))
        return result

    requester_type.request_chat_completion = request
