const form = document.querySelector("#practice-form");
const feedback = document.querySelector("#practice-feedback");

form?.addEventListener("submit", (event) => {
  event.preventDefault();
  const selected = new FormData(form).get("headline");
  if (!selected || !feedback) return;
  const correct = selected === "dated";
  feedback.hidden = false;
  feedback.dataset.outcome = correct ? "correct" : "retry";
  feedback.textContent = correct
    ? "Exactly. Users grew 80% in 2025. The publication date tells you when the report came out, not when the growth happened."
    : "Look at the years in the table. The report was published in 2026, but it measures growth from 2024 to 2025. You can choose again.";
});

form?.addEventListener("change", () => {
  if (!feedback) return;
  feedback.hidden = true;
  feedback.textContent = "";
  delete feedback.dataset.outcome;
});

if (form && feedback) {
  form.querySelector("fieldset").disabled = false;
  const submit = form.querySelector("button");
  submit.type = "submit";
  submit.disabled = false;
}
