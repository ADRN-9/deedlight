import fs from "node:fs";
import path from "node:path";

const layoutPath = path.join(process.cwd(), "app", "layout.tsx");

if (!fs.existsSync(layoutPath)) {
  console.error("Could not find app/layout.tsx. Run this script from the Deedlight project root.");
  process.exit(1);
}

let source = fs.readFileSync(layoutPath, "utf8");
let changed = false;

if (!source.includes("AdminFloatingLink")) {
  const importLine = 'import { AdminFloatingLink } from "@/components/layout/admin-floating-link";\n';

  if (source.includes('import "./globals.css";')) {
    source = source.replace('import "./globals.css";\n', `import "./globals.css";\n${importLine}`);
  } else {
    source = `${importLine}${source}`;
  }

  const mobileNavPattern = /<MobileNav\s*\/?>/;

  if (mobileNavPattern.test(source)) {
    source = source.replace(mobileNavPattern, (match) => `${match}\n        <AdminFloatingLink />`);
  } else if (source.includes("</body>")) {
    source = source.replace("</body>", "        <AdminFloatingLink />\n      </body>");
  } else {
    console.error("Could not safely insert <AdminFloatingLink /> into app/layout.tsx.");
    process.exit(1);
  }

  changed = true;
}

if (changed) {
  fs.writeFileSync(layoutPath, source);
  console.log("Updated app/layout.tsx with AdminFloatingLink.");
} else {
  console.log("app/layout.tsx already includes AdminFloatingLink. No changes made.");
}
