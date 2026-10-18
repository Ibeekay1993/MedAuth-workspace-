import { Link, Route, Routes } from 'react-router-dom';
import { isSupabaseConfigured } from './lib/supabase';

function Landing() {
  return <main className="shell">
    <nav className="nav"><div className="brand-mark">M</div><span className="brand">MedAuth</span><span className="nav-tag">HMO WORKSPACE PLATFORM</span></nav>
    <section className="hero"><p className="eyebrow">HEALTHCARE OPERATIONS, CONNECTED</p><h1>One workspace.<br/><em>Every workflow.</em></h1><p className="lead">A secure workspace for healthcare authorisation, utilisation management, claims and settlement operations.</p><div className="actions"><Link className="button primary" to="/sign-in">Sign in</Link><Link className="button secondary" to="/register">Register an HMO</Link></div>
      {!isSupabaseConfigured && <div className="notice"><strong>Setup required</strong><span>Connect a new MedAuth Supabase project by setting the variables in <code>.env</code>. No existing production database is connected.</span></div>}
    </section>
    <section className="cards"><article><span>01</span><h2>Authorisations</h2><p>Structured pre-authorisation and clinical review workflows.</p></article><article><span>02</span><h2>Claims & settlement</h2><p>Claims review, payment tracking and settlement reporting.</p></article><article><span>03</span><h2>Separate workspaces</h2><p>Tenant isolation designed into the data and permission model.</p></article></section>
    <footer>MedAuth Workspace <span>Independent commercial platform · Initial foundation</span></footer>
  </main>;
}
function Placeholder({ title, text }: {title:string;text:string}) { return <main className="form-shell"><Link to="/" className="back">← MedAuth</Link><p className="eyebrow">WORKSPACE ACCESS</p><h1>{title}</h1><p>{text}</p><div className="notice"><strong>Not connected yet</strong><span>Authentication and tenant provisioning will be enabled after the independent database migration and security policies are installed.</span></div><Link className="button secondary" to="/">Return home</Link></main> }
export default function App() { return <Routes><Route path="/" element={<Landing/>}/><Route path="/sign-in" element={<Placeholder title="Welcome back" text="Sign in to your organisation's workspace."/>}/><Route path="/register" element={<Placeholder title="Create an HMO workspace" text="Register your organisation to begin onboarding."/>}/><Route path="*" element={<Placeholder title="Page not found" text="The page you requested does not exist."/>}/></Routes> }
