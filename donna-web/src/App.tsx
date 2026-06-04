import { useState, type FormEvent } from "react";
import "./App.css";

export default function App() {
  const [email, setEmail] = useState("");
  const [submitted, setSubmitted] = useState(false);

  function handleWaitlist(e: FormEvent) {
    e.preventDefault();
    if (email.trim()) setSubmitted(true);
  }

  return (
    <div className="page">
      <main className="landing">
        <h1>
          AI Second Brain, but the <em>BEST</em>
        </h1>
        <form className="waitlist-form" onSubmit={handleWaitlist}>
          {submitted ? (
            <p className="waitlist-success">You&apos;re on the list.</p>
          ) : (
            <>
              <input
                type="email"
                placeholder="you@email.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                aria-label="Email for waitlist"
              />
              <button type="submit">Join waitlist</button>
            </>
          )}
        </form>
      </main>
    </div>
  );
}
