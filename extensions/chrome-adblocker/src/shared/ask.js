// How the extension's pages ask its service worker for something.

/** Sends a message to the worker and returns its answer; throws with the worker's own words if it refused. */
export async function ask(message) {
  const answer = await chrome.runtime.sendMessage(message);
  if (answer?.error) throw new Error(answer.error);
  return answer;
}
