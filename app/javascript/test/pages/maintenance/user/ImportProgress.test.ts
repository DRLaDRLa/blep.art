import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { describeProgress, watchImportProgress } from "@/pages/maintenance/user/e6ai_favorite_imports/ImportProgress";

function mount (status: string): HTMLElement {
  document.body.innerHTML = `
    <div id="e6ai-import-progress" data-url="/progress.json" data-status="${status}">
      <progress max="100" value="0"></progress>
      <p class="e6ai-import-status"></p>
    </div>`;
  return document.getElementById("e6ai-import-progress");
}

function respondWith (...replies: (object | number | Error)[]) {
  const fetchMock = vi.fn();
  for (const reply of replies) {
    if (reply instanceof Error) fetchMock.mockRejectedValueOnce(reply);
    else if (typeof reply === "number") fetchMock.mockResolvedValueOnce({ ok: false, status: reply, json: async () => ({}) });
    else fetchMock.mockResolvedValueOnce({ ok: true, status: 200, json: async () => reply });
  }
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

const saving = { status: "saving", percent: 25, found_count: 1280, expected_count: 1280 };

it("describes each stage", () => {
  expect(describeProgress({ ...saving, status: "queued" })).toBe("Waiting to start…");
  expect(describeProgress(saving)).toBe("Saving 1,280 favorites…");
});

describe("watchImportProgress", () => {
  const finish = vi.fn();

  beforeEach(() => {
    vi.useFakeTimers();
    finish.mockClear();
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it("moves the bar while the import runs, then shows the finished page", async () => {
    const root = mount("saving");
    const fetchMock = respondWith(saving, { status: "failed", percent: 0, found_count: 0, expected_count: null });
    watchImportProgress(root, 1000, finish);
    await vi.advanceTimersByTimeAsync(1000);
    expect(root.querySelector("progress").value).toBe(25);
    expect(root.querySelector(".e6ai-import-status").textContent).toBe("Saving 1,280 favorites…");
    await vi.advanceTimersByTimeAsync(1000);
    expect(finish).toHaveBeenCalledOnce();
    await vi.advanceTimersByTimeAsync(5000);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("backs off after errors, recovers after a success, and stops once logged out", async () => {
    const fetchMock = respondWith(new Error("offline"), 500, saving, 403);
    watchImportProgress(mount("saving"), 1000, finish);
    await vi.advanceTimersByTimeAsync(1000); // fails: next in 2 s
    await vi.advanceTimersByTimeAsync(1999);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1);    // fails: next in 4 s
    await vi.advanceTimersByTimeAsync(4000); // succeeds: next in 1 s
    await vi.advanceTimersByTimeAsync(1000); // 403: stop
    await vi.advanceTimersByTimeAsync(60_000);
    expect(fetchMock).toHaveBeenCalledTimes(4);
    expect(finish).not.toHaveBeenCalled();
  });

  it("does not poll a finished import, or after being stopped", async () => {
    const fetchMock = respondWith(saving);
    watchImportProgress(mount("done"), 1000, finish);
    watchImportProgress(mount("saving"), 1000, finish)();
    await vi.advanceTimersByTimeAsync(5000);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
