const guidelines = [
  "Share to inspire, not to show superiority.",
  "Protect the dignity of people you helped.",
  "Do not expose vulnerable people without permission.",
  "Do not use suffering as spectacle.",
  "No hate, prejudice, harassment, or political manipulation.",
  "Community needs and fundraising-style posts require extra review.",
  "Anonymous goodness is welcome."
];

export default function GuidelinesPage() {
  return (
    <section className="mx-auto max-w-3xl px-4 py-16 sm:px-6">
      <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Dignity Guidelines</p>
      <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold">Goodness should protect dignity.</h1>
      <div className="mt-8 deed-card p-6 sm:p-8">
        <ul className="space-y-4">
          {guidelines.map((item) => (
            <li key={item} className="rounded-2xl bg-[#FFF8EA] p-4 font-semibold leading-7 text-[#5F5548]">{item}</li>
          ))}
        </ul>
      </div>
    </section>
  );
}
