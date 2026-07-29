type AdminStatusMessageProps = {
  type?: "success" | "warning" | "error" | "info";
  title?: string;
  children: React.ReactNode;
};

const styles = {
  success: "border-emerald-100 bg-emerald-50 text-emerald-950",
  warning: "border-amber-200 bg-amber-50 text-amber-950",
  error: "border-red-100 bg-red-50 text-red-950",
  info: "border-sky-100 bg-sky-50 text-sky-950",
};

export function AdminStatusMessage({
  type = "info",
  title,
  children,
}: AdminStatusMessageProps) {
  return (
    <div className={`rounded-[1.5rem] border p-5 text-sm shadow-sm ${styles[type]}`}>
      {title ? <p className="font-black">{title}</p> : null}
      <div className={title ? "mt-1 leading-7" : "leading-7"}>{children}</div>
    </div>
  );
}
