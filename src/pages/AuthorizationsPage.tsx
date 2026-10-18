import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { Link, useParams } from 'react-router-dom';
import { ArrowLeft, CheckCircle2, ClipboardList, Plus, RefreshCw, ShieldCheck } from 'lucide-react';
import { supabase } from '../lib/supabase';

type ClinicalItem = { id: string; item_type: string; description: string; quantity: number; requested_amount: number | null; approved_amount: number | null; status: string };
type AuthRequest = { id: string; request_number: number; workspace_id: string; hospital_name: string; patient_reference: string; patient_name: string; policy_number: string | null; diagnosis: string; clinical_notes: string | null; priority: string; status: string; decision_notes: string | null; created_at: string; items: ClinicalItem[] };
type Workspace = { id: string; name: string; status: string };
const statuses = ['pending','in_review','approved','partially_approved','declined','cancelled'];
const money = (amount: number | null) => amount == null ? 'Not specified' : new Intl.NumberFormat('en-NG',{style:'currency',currency:'NGN',maximumFractionDigits:2}).format(amount);
const readable = (value: string) => value.replaceAll('_',' ').replace(/\b\w/g, letter=>letter.toUpperCase());

export default function AuthorizationsPage() {
  const { workspaceId } = useParams<{workspaceId:string}>();
  const [workspace,setWorkspace]=useState<Workspace|null>(null);
  const [requests,setRequests]=useState<AuthRequest[]>([]);
  const [selectedId,setSelectedId]=useState<string|null>(null);
  const [filter,setFilter]=useState('all');
  const [loading,setLoading]=useState(true);
  const [saving,setSaving]=useState(false);
  const [error,setError]=useState('');
  const [notice,setNotice]=useState('');
  const [showForm,setShowForm]=useState(false);
  const [hospital,setHospital]=useState('');
  const [patientReference,setPatientReference]=useState('');
  const [patientName,setPatientName]=useState('');
  const [policyNumber,setPolicyNumber]=useState('');
  const [diagnosis,setDiagnosis]=useState('');
  const [clinicalNotes,setClinicalNotes]=useState('');
  const [priority,setPriority]=useState('routine');
  const [itemType,setItemType]=useState('treatment');
  const [itemDescription,setItemDescription]=useState('');
  const [quantity,setQuantity]=useState('1');
  const [requestedAmount,setRequestedAmount]=useState('');
  const [decisionNotes,setDecisionNotes]=useState('');
  const [approvedAmount,setApprovedAmount]=useState('');

  const load = useCallback(async () => {
    if(!supabase || !workspaceId) { setError('Supabase or workspace context is missing.');setLoading(false);return; }
    setLoading(true);setError('');
    const [wResult,rResult]=await Promise.all([
      supabase.from('workspaces').select('id,name,status').eq('id',workspaceId).maybeSingle(),
      supabase.from('authorization_requests').select('id,request_number,workspace_id,hospital_name,patient_reference,patient_name,policy_number,diagnosis,clinical_notes,priority,status,decision_notes,created_at,authorization_items(id,item_type,description,quantity,requested_amount,approved_amount,status)').eq('workspace_id',workspaceId).order('created_at',{ascending:false}).limit(100)
    ]);
    if(wResult.error) setError(wResult.error.message);
    else if(!wResult.data) setError('Workspace not found or access denied.');
    else setWorkspace(wResult.data as Workspace);
    if(rResult.error) setError(rResult.error.message);
    else {
      const rows=(rResult.data??[]) as unknown as Array<Omit<AuthRequest,'items'>&{authorization_items:ClinicalItem[]}>;
      const mapped:AuthRequest[]=rows.map(row=>({...row,items:row.authorization_items??[]}));
      setRequests(mapped);
      setSelectedId(current=>current && mapped.some(row=>row.id===current)?current:mapped[0]?.id??null);
    }
    setLoading(false);
  },[workspaceId]);
  useEffect(()=>{void load();},[load]);

  const selected=requests.find(row=>row.id===selectedId)??null;
  const visible=filter==='all'?requests:requests.filter(row=>row.status===filter);
  const canDecide=selected && ['pending','in_review'].includes(selected.status);

  async function submit(e:FormEvent) {
    e.preventDefault(); if(!supabase||!workspaceId)return;
    setSaving(true);setError('');setNotice('');
    const {data,error:submitError}=await supabase.rpc('submit_authorization_request',{
      p_workspace_id:workspaceId,p_hospital_name:hospital,p_patient_reference:patientReference,
      p_patient_name:patientName,p_policy_number:policyNumber||null,p_diagnosis:diagnosis,
      p_clinical_notes:clinicalNotes||null,p_priority:priority,p_item_type:itemType,
      p_item_description:itemDescription,p_quantity:Number(quantity),
      p_requested_amount:requestedAmount===''?null:Number(requestedAmount)
    });
    if(submitError) setError(submitError.message);
    else {
      setNotice('Authorisation request submitted.');
      setShowForm(false);setHospital('');setPatientReference('');setPatientName('');setPolicyNumber('');
      setDiagnosis('');setClinicalNotes('');setItemDescription('');setQuantity('1');setRequestedAmount('');
      await load(); if(typeof data==='string')setSelectedId(data);
    }
    setSaving(false);
  }

  async function decide(nextDecision:string) {
    if(!supabase||!workspaceId||!selected)return;
    setSaving(true);setError('');setNotice('');
    const itemDecisions=selected.items.map((item,index)=>({
      id:item.id,
      status:nextDecision==='declined'?'declined':'approved',
      approved_amount:nextDecision==='declined'?null:(approvedAmount===''?item.requested_amount:Number(approvedAmount))
    }));
    const {error:decisionError}=await supabase.rpc('decide_authorization_request',{
      p_workspace_id:workspaceId,p_request_id:selected.id,p_decision:nextDecision,
      p_decision_notes:decisionNotes,p_item_decisions:itemDecisions
    });
    if(decisionError)setError(decisionError.message);
    else {setNotice('Clinical decision saved and audit event recorded.');setDecisionNotes('');setApprovedAmount('');await load();}
    setSaving(false);
  }

  return <div className="operations-page">
    <header className="operations-header"><div><Link className="back-link" to="/app"><ArrowLeft size={16}/> Workspace overview</Link><p className="eyebrow">CLINICAL OPERATIONS</p><h1>Authorisations</h1><p>{workspace?.name??'Loading workspace'} · Request review and clinical decision queue</p></div><button className="button secondary" onClick={()=>void load()} disabled={loading}><RefreshCw size={16}/> Refresh</button></header>
    {error&&<div className="alert error" role="alert">{error}</div>}{notice&&<div className="alert success" role="status">{notice}</div>}
    <div className="operations-toolbar"><label className="filter-label">Status <select value={filter} onChange={e=>setFilter(e.target.value)}><option value="all">All requests</option>{statuses.map(s=><option key={s} value={s}>{readable(s)}</option>)}</select></label><button className="button primary" onClick={()=>{setShowForm(v=>!v);setError('');setNotice('')}}><Plus size={16}/>{showForm?'Close form':'New authorisation'}</button></div>
    {showForm&&<form className="record-form" onSubmit={submit}><div className="section-title"><h2>Submit a request</h2><span>Required fields marked *</span></div><div className="form-grid">
      <label>Hospital / provider name *<input value={hospital} onChange={e=>setHospital(e.target.value)} minLength={2} maxLength={200} required/></label>
      <label>Patient reference / ID *<input value={patientReference} onChange={e=>setPatientReference(e.target.value)} maxLength={100} required/></label>
      <label>Patient name *<input value={patientName} onChange={e=>setPatientName(e.target.value)} minLength={2} maxLength={200} required/></label>
      <label>Policy number<input value={policyNumber} onChange={e=>setPolicyNumber(e.target.value)} maxLength={100}/></label>
      <label className="wide-field">Diagnosis / clinical indication *<textarea value={diagnosis} onChange={e=>setDiagnosis(e.target.value)} minLength={2} maxLength={2000} required rows={3}/></label>
      <label>Priority<select value={priority} onChange={e=>setPriority(e.target.value)}><option value="routine">Routine</option><option value="urgent">Urgent</option><option value="emergency">Emergency</option></select></label>
      <label>Requested item type<select value={itemType} onChange={e=>setItemType(e.target.value)}><option value="treatment">Treatment</option><option value="drug">Drug</option><option value="investigation">Investigation</option><option value="procedure">Procedure</option><option value="other">Other</option></select></label>
      <label className="wide-field">Treatment / drug / investigation requested *<input value={itemDescription} onChange={e=>setItemDescription(e.target.value)} minLength={2} maxLength={1000} required/></label>
      <label>Quantity *<input type="number" value={quantity} onChange={e=>setQuantity(e.target.value)} min="0.01" step="0.01" required/></label>
      <label>Requested amount (₦)<input type="number" value={requestedAmount} onChange={e=>setRequestedAmount(e.target.value)} min="0" step="0.01" placeholder="Optional"/></label>
      <label className="wide-field">Clinical notes<textarea value={clinicalNotes} onChange={e=>setClinicalNotes(e.target.value)} rows={2} maxLength={4000}/></label>
    </div><div className="form-actions"><button className="button primary" disabled={saving}>{saving?'Submitting…':'Submit authorisation'}</button></div></form>}
    <div className="authorisation-layout"><section className="request-list"><div className="list-heading"><h2>Request queue</h2><span>{visible.length} records</span></div>{loading?<div className="panel">Loading requests…</div>:visible.length===0?<div className="panel empty"><ClipboardList/><h2>No requests found</h2><p>Submit a request or change the status filter.</p></div>:visible.map(row=><button type="button" key={row.id} className={'request-row '+(row.id===selectedId?'selected':'')} onClick={()=>{setSelectedId(row.id);setDecisionNotes('');setApprovedAmount('')}}><span className="request-row-top"><strong>AUTH-{String(row.request_number).padStart(5,'0')}</strong><span className={'status status-'+row.status}>{readable(row.status)}</span></span><span className="request-patient">{row.patient_name}</span><span className="request-diagnosis">{row.diagnosis}</span><span className="request-meta">{row.hospital_name} · {new Date(row.created_at).toLocaleDateString()}</span></button>)}</section>
    <section className="request-detail">{!selected?<div className="panel empty"><ClipboardList/><h2>Select a request</h2><p>Choose a record from the queue to review its clinical details.</p></div>:<><div className="detail-title"><div><p className="eyebrow">AUTH-{String(selected.request_number).padStart(5,'0')}</p><h2>{selected.patient_name}</h2><p>{selected.hospital_name} · {selected.patient_reference}</p></div><span className={'status status-'+selected.status}>{readable(selected.status)}</span></div><div className="detail-section"><h3>Clinical details</h3><dl className="detail-grid"><dt>Diagnosis</dt><dd>{selected.diagnosis}</dd><dt>Policy number</dt><dd>{selected.policy_number||'Not provided'}</dd><dt>Priority</dt><dd>{readable(selected.priority)}</dd><dt>Submitted</dt><dd>{new Date(selected.created_at).toLocaleString()}</dd><dt>Clinical notes</dt><dd>{selected.clinical_notes||'No additional notes'}</dd></dl></div><div className="detail-section"><h3>Requested items</h3>{selected.items.map(item=><article className="clinical-item" key={item.id}><div><span className="item-type">{readable(item.item_type)}</span><h4>{item.description}</h4><p>Quantity: {item.quantity} · Requested: {money(item.requested_amount)}</p>{item.approved_amount!==null&&<p>Approved amount: {money(item.approved_amount)}</p>}</div><span className={'status status-'+item.status}>{readable(item.status)}</span></article>)}</div>{selected.decision_notes&&<div className="decision-note"><strong>Decision notes</strong><p>{selected.decision_notes}</p></div>}
    {canDecide&&<div className="decision-panel"><h3>Clinical decision</h3><p>Review the request and record a reason or conditions. Decisions lock clinical details; corrections require a new request.</p><label>Approved amount (₦)<input type="number" value={approvedAmount} onChange={e=>setApprovedAmount(e.target.value)} min="0" step="0.01" placeholder={selected.items[0]?.requested_amount==null?'Not specified':String(selected.items[0].requested_amount)}/></label><label>Decision notes<textarea value={decisionNotes} onChange={e=>setDecisionNotes(e.target.value)} rows={3} maxLength={4000} placeholder="Clinical rationale, limits or instructions"/></label><div className="decision-actions"><button className="button primary" disabled={saving} onClick={()=>{void decide('approved')}}><CheckCircle2 size={16}/> Approve</button><button className="button secondary" disabled={saving} onClick={()=>{void decide('partially_approved')}}>Partially approve</button><button className="button danger" disabled={saving} onClick={()=>{void decide('declined')}}>Decline</button></div></div>}
    {!canDecide&&<div className="locked-notice"><ShieldCheck size={18}/><span>This request has been decided. Clinical details are locked.</span></div>}</>}</section></div>
  </div>;
}
