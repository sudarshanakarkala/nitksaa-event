/**
 * NITKSAA event sheet templates.
 *
 * One run makes three Google Sheets in your Drive:
 *   - NITKSAA event sheet – Blank
 *   - NITKSAA event sheet – Breakfast example
 *   - NITKSAA event sheet – NITKonnect example
 * The log lists each one's link and its "copy" link (share the copy link:
 * it opens straight to "Make a copy").
 *
 * How to run (as nitksaa.infra@gmail.com): script.google.com → New project →
 * paste this file → Save → choose makeTemplates → Run → allow access
 * (Advanced → Go to … if Google warns: it's your own script).
 * Then share each sheet: General access → Anyone with the link → Viewer.
 *
 * The events app reads tabs by name and columns by their header words, so
 * keep those; the order of columns, extra columns and blank rows don't matter.
 */

const SERVICE_ACCOUNT = 'nitksaa-events-api@project-d22bed42-f302-4e23-8dc.iam.gserviceaccount.com';
const TEMPLATE_VERSION = '2';
const ROWS = 300;

const LOOK = { header: '#e8eaed', headerText: '#202124', help: '#80868b', fold: '#f8f9fa' };

const SESSION_TYPES = ['Keynote', 'Talk', 'Panel', 'Fireside', 'Workshop', 'Showcase', 'Networking', 'Awards', 'Break'];
const ROLES = ['Speaker', 'Panelist', 'Moderator', 'Chief guest', 'Guest of honour', 'Host'];
const TIERS = [
  'Title sponsor', 'Gold sponsor', 'Silver sponsor', 'Bronze sponsor', 'Associate sponsor',
  'Community partner', 'Knowledge partner', 'Media partner', 'Venue partner',
  'Technology partner', 'Ecosystem partner', 'Hiring partner',
];

// `more: true` columns are folded away behind the "+" until someone needs them.
const SESSIONS = [
  { name: 'Date', kind: 'date', width: 105, note: 'Blank for a one-day event. For several days, the session\'s date, e.g. 15 Nov 2026.' },
  { name: 'Start', kind: 'time', width: 80, required: true, note: 'e.g. 9:30 or 2:15 pm.' },
  { name: 'End', kind: 'time', width: 80, note: 'Optional. Blank: until the next session starts.' },
  { name: 'Title', kind: 'long', width: 280, required: true, note: 'The session\'s name.' },
  { name: 'Speakers', kind: 'long', width: 260, note: 'Names, separated by commas, as on the Speakers tab.\n\nMore columns for big events (type, hall, moderator…): press + above the column letters.' },
  { name: 'Moderator', kind: 'text', width: 150, more: true, note: 'Name(s) as on the Speakers tab.' },
  { name: 'Type', kind: 'list', values: SESSION_TYPES, width: 105, more: true, note: 'Break shows as a band across the agenda.' },
  { name: 'Hall', kind: 'text', width: 100, more: true, note: 'For parallel sessions, e.g. Hall A.' },
  { name: 'Pillar', kind: 'text', width: 130, more: true, note: 'A theme, e.g. Career Konnect. Attendees can filter by it.' },
  { name: 'Subtitle', kind: 'long', width: 240, more: true, note: 'A second line under the title.' },
  { name: 'Presented by', kind: 'text', width: 170, more: true, note: 'Sponsor names, separated by commas, as on the Sponsors tab.' },
];

const SPEAKERS = [
  { name: 'Name', kind: 'text', width: 190, required: true, note: 'Each person once.' },
  { name: 'Title', kind: 'text', width: 200, note: 'Job title, e.g. CTO.' },
  { name: 'Company', kind: 'text', width: 180, note: '' },
  { name: 'Email', kind: 'email', width: 210, note: 'For organisers only, never shown on the event page. For NITK alumni, the app fills in their batch, LinkedIn and phone.\n\nMore columns (role, photo, bio…): press + above the column letters.' },
  { name: 'Role', kind: 'list', values: ROLES, width: 120, more: true, note: 'Blank means Speaker.' },
  { name: 'Phone', kind: 'text', width: 130, more: true, note: 'For organisers only.' },
  { name: 'LinkedIn', kind: 'link', width: 200, more: true, note: 'Starting https://' },
  { name: 'Photo link', kind: 'link', width: 200, more: true, note: 'A link to a square photo, starting https://' },
  { name: 'Batch', kind: 'text', width: 120, more: true, note: 'e.g. Mech 1998. Blank: from the alumni directory.' },
  { name: 'Bio', kind: 'long', width: 300, more: true, note: 'A few lines.' },
];

const SPONSORS = [
  { name: 'Name', kind: 'text', width: 200, required: true, note: 'Each sponsor or partner once.' },
  { name: 'Tier', kind: 'list', values: TIERS, width: 160, required: true, note: 'Sponsors are grouped by tier; partners are listed with the partners.' },
  { name: 'Logo link', kind: 'link', width: 220, note: 'Starting https://' },
  { name: 'Website', kind: 'link', width: 200, note: 'Starting https://' },
  { name: 'Label', kind: 'text', width: 150, note: 'Optional. Shown instead of the tier, e.g. Co-presenter.' },
];

// Event tab: read when an event is imported (Events → Import); after that
// these are changed in the app. The gap is read on every Refresh.
const EVENT_MAIN = [
  { name: 'Title', kind: 'text', required: true, help: 'The event\'s name.' },
  { name: 'Date', kind: 'date', required: true, help: 'e.g. 15 Nov 2026.' },
  { name: 'Start time', kind: 'time', help: 'e.g. 7:30 am. Both times blank: a full-day event.' },
  { name: 'End time', kind: 'time', help: 'e.g. 9:30 am.' },
  { name: 'Venue', kind: 'long', help: 'Name and address. Blank for an online event (put the Meeting link below).' },
  { name: 'Capacity', kind: 'whole', required: true, help: 'Most people who can come, guests included.' },
  { name: 'Ticket price (₹)', kind: 'number', help: 'Blank or 0: free.' },
  { name: 'Guests per registration', kind: 'list', values: ['0', '1', '2', '3', '4'], help: 'Blank: 0.' },
];
const EVENT_MORE = [
  { name: 'End date', kind: 'date', help: 'Only for an event over several days.' },
  { name: 'Timezone', kind: 'text', help: 'Blank: India (Asia/Kolkata).' },
  { name: 'Map link', kind: 'link', help: 'A Google Maps link to the venue.' },
  { name: 'Meeting link', kind: 'link', help: 'For an online event; shown only to registered people.' },
  { name: 'Registration opens', kind: 'datetime', help: 'Blank: when published.' },
  { name: 'Registration closes', kind: 'datetime', help: 'Blank: when the event starts.' },
  { name: 'Description', kind: 'long', help: '**bold**, ## headings, - lists and [links](https://…) work.' },
  { name: 'Thumbnail link', kind: 'link', help: 'Small image on the event card.' },
  { name: 'Banner link', kind: 'link', help: 'Wide image on the event page (about 1600×400).' },
  { name: 'Logo link', kind: 'link', help: 'Logo for light backgrounds.' },
  { name: 'Logo link (dark backgrounds)', kind: 'link', help: 'A white version of the logo.' },
  { name: 'Gap between sessions (minutes)', kind: 'gap', help: 'Sessions without an End stop this many minutes before the next one.' },
];

const EXAMPLES = {
 "breakfast": {
  "event": {
   "Title": "November Biz Breakfast",
   "Date": "15 Nov 2026",
   "Start time": "7:30 am",
   "End time": "9:30 am",
   "Venue": "BHIVE Workspace, Church Street, Bengaluru",
   "Capacity": "75",
   "Ticket price (₹)": "100",
   "Guests per registration": "0",
   "Description": "**NITKSAA Bangalore Chapter · November Biz Breakfast Meeting**\n\nThe startup and entrepreneurship ecosystem is navigating unprecedented shifts driven by rapid AI advancements, global macro developments and evolving capital environments.\n## What we'll discuss\nHow are these forces reshaping:\n- venture strategy\n- go-to-market dynamics\n- funding pipelines\n- mentorship\n\nJoin us for an insightful morning of candid discussions, real-world playbooks and high-impact networking with industry leaders.\n## Good to know\n- A collaborative initiative of the **Bangalore Alumni Chapters of various NITs**\n- **Limited to 75 registrations**\n\nSee you over breakfast for great conversations and meaningful connections!"
  },
  "sessions": [
   [
    "",
    "7:30 am",
    "",
    "Registration and networking breakfast",
    "",
    "",
    "Networking",
    "",
    "",
    "",
    ""
   ],
   [
    "",
    "8:00 am",
    "",
    "Welcome",
    "Host Name",
    "",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "",
    "8:10 am",
    "",
    "Panel: Startups in the AI era",
    "Panelist One, Panelist Two, Panelist Three",
    "Moderator Name",
    "Panel",
    "",
    "",
    "Venture strategy, go-to-market and funding",
    ""
   ],
   [
    "",
    "9:00 am",
    "9:30 am",
    "Open discussion and networking",
    "",
    "",
    "Networking",
    "",
    "",
    "",
    ""
   ]
  ],
  "speakers": [
   [
    "Host Name",
    "Chapter Secretary",
    "NITKSAA Bangalore",
    "",
    "Host",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Panelist One",
    "Founder",
    "Example Startup",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Panelist Two",
    "Partner",
    "Example Ventures",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Panelist Three",
    "Head of Product",
    "Example Corp",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Moderator Name",
    "Mentor",
    "",
    "",
    "Moderator",
    "",
    "",
    "",
    "",
    ""
   ]
  ],
  "sponsors": []
 },
 "nitkonnect": {
  "event": {
   "Title": "NITKonnect 2026",
   "Date": "21 Feb 2026",
   "Start time": "8:00 am",
   "End time": "9:30 pm",
   "Venue": "Taj Yeshwantpur, Bengaluru",
   "Capacity": "1000",
   "Ticket price (₹)": "2500",
   "Guests per registration": "0",
   "Description": "KreditBee presents NITKonnect 26, co-presented by RT Energy and BHIVE.\n\nA full day of keynotes, CXO panels, startup showcases, career sessions and the NITK Awards, ending with music, drinks and dinner.\n\n1000+ delegates · 350+ founders · 200+ CXOs · 100+ angel investors · 60+ startups\n\nThree pillars\n• Main Event: keynotes, CXO panels on global scaling, startup showcases, the Founders' Panel and the NITK Awards.\n• Career Konnect: sessions with mentors on alternative careers, life stages and hiring.\n• Startup Showcase: three Investor Konnect sessions with 16 startups, an LP roundtable, and social entrepreneurship.\n\nExample data from the NITKonnect 2026 brochure.",
   "Banner link": "https://events.nitkalumni.in/brand/nitkonnect/banner.png",
   "Logo link": "https://events.nitkalumni.in/brand/nitkonnect/logo.png",
   "Logo link (dark backgrounds)": "https://events.nitkalumni.in/brand/nitkonnect/logo_white.png",
   "Gap between sessions (minutes)": "0"
  },
  "sessions": [
   [
    "21 Feb 2026",
    "8:00 am",
    "8:15 am",
    "Registrations",
    "",
    "",
    "",
    "Main Hall",
    "",
    "",
    ""
   ],
   [
    "21 Feb 2026",
    "8:15 am",
    "9:25 am",
    "Networking Breakfast with Career Mentors & Startup Mentors",
    "",
    "",
    "Networking",
    "Main Hall",
    "Main Event",
    "",
    ""
   ],
   [
    "21 Feb 2026",
    "9:25 am",
    "9:40 am",
    "Welcome & Introduction",
    "",
    "",
    "Talk",
    "Main Hall",
    "Main Event",
    "",
    ""
   ],
   [
    "21 Feb 2026",
    "9:40 am",
    "9:50 am",
    "Director's Address",
    "Prof Ravi B",
    "",
    "Keynote",
    "Main Hall",
    "Main Event",
    "",
    ""
   ],
   [
    "21 Feb 2026",
    "9:50 am",
    "10:20 am",
    "Startup Showcase",
    "",
    "",
    "Showcase",
    "Main Hall",
    "Startup Showcase",
    "",
    ""
   ],
   [
    "21 Feb 2026",
    "10:20 am",
    "10:40 am",
    "Global Alumni President Talk & Sponsor Felicitation",
    "",
    "",
    "Talk",
    "Main Hall",
    "Main Event",
    "",
    ""
   ],
   [
    "21 Feb 2026",
    "10:40 am",
    "10:55 am",
    "Fireside Chat: From Campus to Cross-Border Deals",
    "Deepak Dhar, Saumya Swain",
    "",
    "Fireside",
    "Main Hall",
    "Main Event",
    "An NITKian's Journey",
    ""
   ],
   [
    "21 Feb 2026",
    "10:55 am",
    "11:40 am",
    "Innovate in Bharat, Scale for the World",
    "Ankit Saran, Navin Bishnoi, Anand Narayanan, Susheel Navanale, Krishnamurthy Ramamurthy",
    "",
    "Panel",
    "Hall A",
    "Main Event",
    "The Next Growth Mandate",
    ""
   ],
   [
    "21 Feb 2026",
    "10:55 am",
    "11:40 am",
    "AI Workshop by Lyzr",
    "",
    "",
    "Workshop",
    "Hall B",
    "Main Event",
    "",
    "Lyzr"
   ],
   [
    "21 Feb 2026",
    "10:55 am",
    "11:40 am",
    "LP Roundtable",
    "",
    "",
    "Panel",
    "Hall C",
    "Startup Showcase",
    "",
    "IdeaSpring Capital, Warmup Ventures"
   ],
   [
    "21 Feb 2026",
    "11:40 am",
    "12:15 pm",
    "Networking Tea 1",
    "",
    "",
    "Break",
    "Main Hall",
    "",
    "",
    ""
   ],
   [
    "21 Feb 2026",
    "12:15 pm",
    "1:00 pm",
    "Energy & Sustainability: Powering Bharat",
    "Nitin Sharma, Krishna Revankar, Rudresha MV, Dr. Ajay Mehta, Anil Rajanna",
    "",
    "Panel",
    "Hall A",
    "Main Event",
    "Clean Energy at Scale",
    ""
   ],
   [
    "21 Feb 2026",
    "12:15 pm",
    "1:00 pm",
    "From Sky to Space",
    "Ravishankar Mysore, R. V. Nadagouda, Sumit Rishi, Sohan Suvarna, Kishora Shetty",
    "",
    "Panel",
    "Hall B",
    "Main Event",
    "Building India's Self-Reliance Engine",
    ""
   ],
   [
    "21 Feb 2026",
    "12:15 pm",
    "1:00 pm",
    "From 'Plus One' to 'The One'",
    "Nitin Gupta, Krishna BS, K G Ashok Rao, Hariharan Krishnamoorthy",
    "",
    "Panel",
    "Hall C",
    "Main Event",
    "Making India the Factory of the Future",
    ""
   ],
   [
    "21 Feb 2026",
    "1:00 pm",
    "2:00 pm",
    "Networking Lunch",
    "",
    "",
    "Break",
    "Main Hall",
    "",
    "",
    ""
   ],
   [
    "21 Feb 2026",
    "2:00 pm",
    "2:45 pm",
    "India's AI Sovereignty",
    "Satish Grampurohit, Sharath Adavanne, Kalyan Sivasailam, Pankaj Kankar, Vageesh Hoskere",
    "",
    "Panel",
    "Hall A",
    "Main Event",
    "From Consumers to Creators",
    "5C Network"
   ],
   [
    "21 Feb 2026",
    "2:00 pm",
    "2:45 pm",
    "FinTech 2030",
    "Almas Parveen, Arjun Zacharia, Sushma Arani, Prateek Goyal, Sidharth Vishwanathan",
    "",
    "Panel",
    "Hall B",
    "Main Event",
    "From Disruption to Digital Infrastructure of Bharat",
    ""
   ],
   [
    "21 Feb 2026",
    "2:00 pm",
    "2:45 pm",
    "The EV Pivot",
    "RK Shenoy, Prashant Sankeshwar, Sudarshana Karkala, Rajendra Bhat",
    "",
    "Panel",
    "Hall C",
    "Main Event",
    "Can India Lead the Global Electric Revolution?",
    "Veera Vahana"
   ],
   [
    "21 Feb 2026",
    "2:00 pm",
    "2:45 pm",
    "Panel Discussion: Alternative Careers",
    "Shankar Prakash, Chandrashekar, Lakshmi Pradeep, Pranay Kotasthane, Venkatesha Murthy",
    "",
    "Panel",
    "Hall D",
    "Career Konnect",
    "Beyond the Default Path",
    ""
   ],
   [
    "21 Feb 2026",
    "2:00 pm",
    "2:45 pm",
    "Investor Konnect - Part 1",
    "",
    "",
    "Showcase",
    "Hall E",
    "Startup Showcase",
    "3 startups",
    ""
   ],
   [
    "21 Feb 2026",
    "2:45 pm",
    "3:30 pm",
    "AI + Humans",
    "Prashanth Kaddi, Srinivas Bhimaraju, Rakesh Ravuri, Manish Kumar, Swapnil Disawal",
    "",
    "Panel",
    "Hall A",
    "Main Event",
    "Redefining Work for Next Decade",
    ""
   ],
   [
    "21 Feb 2026",
    "2:45 pm",
    "3:30 pm",
    "Backing Bharat at Scale",
    "Kailashnath MS, Arjun Rao, Riaz Maniyar, Girichandra K, Rohan Choukkar",
    "",
    "Panel",
    "Hall B",
    "Main Event",
    "Where Capital Meets Conviction — and Innovation",
    ""
   ],
   [
    "21 Feb 2026",
    "2:45 pm",
    "3:30 pm",
    "Built in Bharat, Trusted by the World",
    "Smruti Parida, Srinivasa Bharathy, Lakshmipathy RK, Dr. Narasimha Kamath, Harsh Singla",
    "",
    "Panel",
    "Hall C",
    "Main Event",
    "Enterprise SaaS Moment",
    "Keacyte"
   ],
   [
    "21 Feb 2026",
    "2:45 pm",
    "3:30 pm",
    "Panel Discussion: What No One Tells You at 25, 35, and 45",
    "Ashok Nair, Santosh Huralikoppi, Sandeep Zuthshi, Rudramuni B, Prasad Acharya",
    "",
    "Panel",
    "Hall D",
    "Career Konnect",
    "",
    ""
   ],
   [
    "21 Feb 2026",
    "2:45 pm",
    "3:30 pm",
    "Investor Konnect - Part 2",
    "",
    "",
    "Showcase",
    "Hall E",
    "Startup Showcase",
    "3 startups",
    ""
   ],
   [
    "21 Feb 2026",
    "3:30 pm",
    "4:15 pm",
    "Sector Huddle: Deploying AI at Scale",
    "Jithin George, Raghavendra Narayan, Srinidhi Shama Rao, Jayant Prabhu",
    "",
    "Panel",
    "Hall A",
    "Main Event",
    "From Pilots to Production",
    "Lyzr"
   ],
   [
    "21 Feb 2026",
    "3:30 pm",
    "4:15 pm",
    "Silicon to System",
    "Amit Ashok Hattangadi, Girish Desai, Dheemanth Nagaraj, Venkatesh TS",
    "",
    "Panel",
    "Hall B",
    "Main Event",
    "India's Electronics Future",
    "SierraEdge AI"
   ],
   [
    "21 Feb 2026",
    "3:30 pm",
    "4:15 pm",
    "From Brand to Community",
    "Anurag Sinha, Raghu Reddy, Umesh Bude, Saurabh Mahajan, Rohini Naik",
    "",
    "Panel",
    "Hall C",
    "Main Event",
    "The New Consumer Playbook in Bharat",
    ""
   ],
   [
    "21 Feb 2026",
    "3:30 pm",
    "4:15 pm",
    "Hiring Konnect",
    "",
    "",
    "Networking",
    "Hall D",
    "Career Konnect",
    "Platform to hire and get hired",
    ""
   ],
   [
    "21 Feb 2026",
    "3:30 pm",
    "4:15 pm",
    "Investor Konnect - Part 3",
    "",
    "",
    "Showcase",
    "Hall E",
    "Startup Showcase",
    "4 startups",
    ""
   ],
   [
    "21 Feb 2026",
    "4:15 pm",
    "4:50 pm",
    "Networking Tea 2",
    "",
    "",
    "Break",
    "Main Hall",
    "",
    "",
    ""
   ],
   [
    "21 Feb 2026",
    "4:50 pm",
    "5:10 pm",
    "Key Address",
    "Shesh Rao Paplikar, Lovaii Navlakhi",
    "",
    "Keynote",
    "Hall A",
    "Main Event",
    "",
    ""
   ],
   [
    "21 Feb 2026",
    "4:50 pm",
    "5:10 pm",
    "Hiring Konnect",
    "",
    "",
    "Networking",
    "Hall B",
    "Career Konnect",
    "Platform to hire and get hired",
    ""
   ],
   [
    "21 Feb 2026",
    "4:50 pm",
    "5:10 pm",
    "Fireside Chat with Ankur Rawal",
    "Ankur Rawal",
    "",
    "Fireside",
    "Hall C",
    "Main Event",
    "From Pivot to Acquisition",
    ""
   ],
   [
    "21 Feb 2026",
    "5:10 pm",
    "5:20 pm",
    "Founders' Panel",
    "Jitendra Jagadev, G Shankar Ramm, Raghunandan, Ghanshyam Tiwari, Deepak Shenoy",
    "",
    "Panel",
    "Main Hall",
    "Main Event",
    "Built in Bharat, Scaling Without Shortcuts",
    ""
   ],
   [
    "21 Feb 2026",
    "5:20 pm",
    "5:55 pm",
    "Trails, Tears and Transformations",
    "",
    "",
    "Talk",
    "Main Hall",
    "Startup Showcase",
    "in Social Entrepreneurship and Careers",
    ""
   ],
   [
    "21 Feb 2026",
    "5:55 pm",
    "6:10 pm",
    "Keynote: Bharat Unbound",
    "Ajay Prabhu",
    "",
    "Keynote",
    "Main Hall",
    "Main Event",
    "Engineering as a Global Growth Engine",
    ""
   ],
   [
    "21 Feb 2026",
    "6:10 pm",
    "6:40 pm",
    "NITK Awards | Konnect Team Photo ops",
    "",
    "",
    "Awards",
    "Main Hall",
    "Main Event",
    "",
    ""
   ],
   [
    "21 Feb 2026",
    "6:40 pm",
    "7:40 pm",
    "Engagement Activities",
    "",
    "",
    "",
    "Main Hall",
    "Main Event",
    "Standup Comic & Mimicry Act",
    ""
   ],
   [
    "21 Feb 2026",
    "7:40 pm",
    "9:30 pm",
    "Music, Drinks & Dinner",
    "",
    "",
    "Networking",
    "Main Hall",
    "Main Event",
    "Curtains at 21:30",
    ""
   ]
  ],
  "speakers": [
   [
    "Prof Ravi B",
    "Director",
    "NITK Surathkal",
    "",
    "Chief guest",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Deepak Dhar",
    "Founder",
    "Repute Networks",
    "",
    "Speaker",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Saumya Swain",
    "Chairman",
    "RT Energy",
    "",
    "Speaker",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Ankit Saran",
    "Partner",
    "Deloitte",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Navin Bishnoi",
    "Country Head",
    "Marvell India",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Anand Narayanan",
    "Head of Product",
    "Atlassian",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Susheel Navanale",
    "CIO",
    "Britannia Industries",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Krishnamurthy Ramamurthy",
    "Sr. Managing Director",
    "Accenture",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Nitin Sharma",
    "Co-Founder & Director",
    "Newen Systems",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Krishna Revankar",
    "MD & Founder",
    "Balark Solar Private Ltd",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Rudresha MV",
    "MD",
    "Aspen Technology",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Dr. Ajay Mehta",
    "VP Research & Innovation",
    "Shell",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Anil Rajanna",
    "CEO | Entrepreneur | Board Member",
    "ELEKTRON",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Ravishankar Mysore",
    "Formerly VP Engineering",
    "Collins Aerospace",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "R. V. Nadagouda",
    "Distinguished Scientist, Associate Director - Projects",
    "URSC-ISRO",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Sumit Rishi",
    "Founder & CEO",
    "AerX Labs",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Sohan Suvarna",
    "Techpreneur",
    "",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Kishora Shetty",
    "Global Technology Leader and Associate Technical Fellow",
    "Boeing India",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Nitin Gupta",
    "Global CEO and Executive Director",
    "STEER Engineering Pvt. Ltd.",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Krishna BS",
    "GM Operations - India & South Asia",
    "GE Healthcare",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "K G Ashok Rao",
    "MD",
    "KGK Engineering",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Hariharan Krishnamoorthy",
    "Executive Director",
    "Megawin Switchgear Pvt. Ltd.",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Satish Grampurohit",
    "Co-founder",
    "Cogniquest AI",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Sharath Adavanne",
    "Co-Founder",
    "UPRIO",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Kalyan Sivasailam",
    "Founder and CEO",
    "5C Network",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Pankaj Kankar",
    "CTO",
    "Asper.AI",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Vageesh Hoskere",
    "Director of Engineering",
    "Soroco",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Almas Parveen",
    "Chief of Staff",
    "RazorpayX",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Arjun Zacharia",
    "Founder",
    "EximPe",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Sushma Arani",
    "Product Manager",
    "Clear",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Prateek Goyal",
    "Chief Strategy Officer",
    "Jiraaf",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Sidharth Vishwanathan",
    "Chief Risk Officer",
    "KreditBee",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "RK Shenoy",
    "Former CTO, SVP Mobility Engg",
    "BOSCH",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Prashant Sankeshwar",
    "Vice President - Sales & Network Development",
    "Ultraviolette Automotive",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Sudarshana Karkala",
    "Principal Architect",
    "iTelematics",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Rajendra Bhat",
    "Head Service",
    "Ola Electric",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Shankar Prakash",
    "International Anchor/Compere, Cricket Commentator, Olympian Broadcaster",
    "",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Chandrashekar",
    "Cinematographer + Photographer",
    "",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Lakshmi Pradeep",
    "Singer + Product Manager",
    "Lowe's India",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Pranay Kotasthane",
    "Deputy Director and Chairperson",
    "Takshashila Institution",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Venkatesha Murthy",
    "Founder and Chief Mentor",
    "Youth for Seva",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Prashanth Kaddi",
    "Partner",
    "Deloitte",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Srinivas Bhimaraju",
    "Head, Global Application Services Practice",
    "NTT DATA",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Rakesh Ravuri",
    "CTO, Head of AI Products, and SVP",
    "Publicis Sapient",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Manish Kumar",
    "VP & India Site Head",
    "Okta",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Swapnil Disawal",
    "Sr. Director Engineering",
    "NICE",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Kailashnath MS",
    "Partner",
    "Ideaspring Capital",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Arjun Rao",
    "General Partner",
    "Speciale Invest",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Riaz Maniyar",
    "Managing Partner",
    "Alphaleo Ventures",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Girichandra K",
    "Experienced Early stage VC investor",
    "",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Rohan Choukkar",
    "",
    "Bharat Innovation Fund",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Smruti Parida",
    "Founder",
    "Keacyte",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Srinivasa Bharathy",
    "MD & CEO",
    "Adrenalin",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Lakshmipathy RK",
    "Director GCC",
    "InfoBeans",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Dr. Narasimha Kamath",
    "EVP R&D",
    "O9 Solutions",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Harsh Singla",
    "Regional Sales Director",
    "Confluent",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Ashok Nair",
    "Executive Coach, PCC (ICF), Hogan Certified",
    "",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Santosh Huralikoppi",
    "CEO NS Infotech, Chief Mentor",
    "FUEL",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Sandeep Zuthshi",
    "Founder and Principal Consultant",
    "ZA Consulting",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Rudramuni B",
    "Angel Investor",
    "Inflection Point Ventures",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Prasad Acharya",
    "Vice President",
    "Capgemini India",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Jithin George",
    "CTO & Head of Engineering",
    "Lyzr",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Raghavendra Narayan",
    "Director of Engineering",
    "McDonald's India GCC",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Srinidhi Shama Rao",
    "Founder",
    "CogitX.ai",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Jayant Prabhu",
    "Managing Director",
    "Accenture",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Amit Ashok Hattangadi",
    "Head of Engineering",
    "Synthesis Winding Technologies",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Girish Desai",
    "Founder & CEO",
    "SierraEdge AI",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Dheemanth Nagaraj",
    "Co-founder & CEO",
    "Agrani Labs",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Venkatesh TS",
    "Sr. Director",
    "Samsung Semiconductor",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Anurag Sinha",
    "Director, Chief Executive Officer",
    "WealthNest.AI",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Raghu Reddy",
    "Co-Founder",
    "Lumio",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Umesh Bude",
    "CTO",
    "Pocket FM",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Saurabh Mahajan",
    "Product Management",
    "Myntra",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Rohini Naik",
    "Demand Head",
    "FirstClub",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Shesh Rao Paplikar",
    "Founder",
    "BHIVE",
    "",
    "Speaker",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Lovaii Navlakhi",
    "",
    "IMMPL",
    "",
    "Speaker",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Ankur Rawal",
    "Co-Founder at Zenduty and VP Engineering",
    "Xurrent",
    "",
    "Speaker",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Jitendra Jagadev",
    "Co-founder and CEO",
    "NestAway",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "G Shankar Ramm",
    "Cofounder & MD",
    "PEPS",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Raghunandan",
    "Founder",
    "Zolve",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Ghanshyam Tiwari",
    "Founder, GoodED; Spokesperson, Samajwadi Party",
    "",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Deepak Shenoy",
    "Founder",
    "Capitalmind",
    "",
    "Panelist",
    "",
    "",
    "",
    "",
    ""
   ],
   [
    "Ajay Prabhu",
    "Vice Chairman",
    "Quest Global",
    "",
    "Speaker",
    "",
    "",
    "",
    "",
    ""
   ]
  ],
  "sponsors": [
   [
    "KreditBee",
    "Title sponsor",
    "",
    "",
    ""
   ],
   [
    "RT Energy",
    "Gold sponsor",
    "",
    "",
    "Co-presenter"
   ],
   [
    "BHIVE",
    "Gold sponsor",
    "",
    "",
    "Co-presenter"
   ],
   [
    "International Money Matters",
    "Associate sponsor",
    "",
    "",
    ""
   ],
   [
    "Black & White",
    "Associate sponsor",
    "",
    "",
    ""
   ],
   [
    "SierraEdge AI",
    "Silver sponsor",
    "",
    "",
    ""
   ],
   [
    "Zopper",
    "Associate sponsor",
    "",
    "",
    ""
   ],
   [
    "Veera Vahana",
    "Silver sponsor",
    "",
    "",
    ""
   ],
   [
    "Keacyte",
    "Silver sponsor",
    "",
    "",
    ""
   ],
   [
    "Delhivery",
    "Associate sponsor",
    "",
    "",
    ""
   ],
   [
    "Lyzr",
    "Silver sponsor",
    "",
    "",
    ""
   ],
   [
    "IdeaSpring Capital",
    "Silver sponsor",
    "",
    "",
    ""
   ],
   [
    "Warmup Ventures",
    "Silver sponsor",
    "",
    "",
    ""
   ],
   [
    "5C Network",
    "Silver sponsor",
    "",
    "",
    ""
   ],
   [
    "ESC Plan",
    "Associate sponsor",
    "",
    "",
    ""
   ]
  ]
 }
};


function makeTemplates() {
  const made = [
    build('NITKSAA event sheet – Blank', null, false),
    build('NITKSAA event sheet – Breakfast example', EXAMPLES.breakfast, false),
    build('NITKSAA event sheet – NITKonnect example', EXAMPLES.nitkonnect, true),
  ];
  made.forEach(function (ss) {
    const url = ss.getUrl();
    Logger.log(ss.getName() + '\n  open: ' + url + '\n  copy link to share: ' + url.replace(/\/edit.*$/, '') + '/copy');
  });
}

function build(name, example, open) {
  const ss = SpreadsheetApp.create(name);
  ss.setSpreadsheetTimeZone('Asia/Kolkata');
  ss.setSpreadsheetLocale('en_IN');
  const first = ss.getSheets()[0];
  buildHowTo(first);
  buildEvent(ss.insertSheet('Event'), example ? example.event : null, open);
  buildList(ss.insertSheet('Sessions'), SESSIONS, example ? example.sessions : [], open);
  buildList(ss.insertSheet('Speakers'), SPEAKERS, example ? example.speakers : [], open);
  buildList(ss.insertSheet('Sponsors'), SPONSORS, example ? example.sponsors : [], open);
  ss.setActiveSheet(ss.getSheetByName(example ? 'Sessions' : 'How to fill'));
  SpreadsheetApp.flush();
  return ss;
}

function buildList(sh, columns, data, open) {
  const width = columns.length;
  sh.deleteColumns(width + 1, sh.getMaxColumns() - width);
  if (sh.getMaxRows() > ROWS) sh.deleteRows(ROWS + 1, sh.getMaxRows() - ROWS);

  const header = sh.getRange(1, 1, 1, width);
  header.setValues([columns.map(function (c) { return c.required ? c.name + ' *' : c.name; })])
    .setFontWeight('bold').setFontColor(LOOK.headerText).setBackground(LOOK.header)
    .setVerticalAlignment('middle');
  sh.setRowHeight(1, 30);
  sh.setFrozenRows(1);
  header.protect().setDescription('Column names: the events app reads these').setWarningOnly(true);
  sh.getRange(2, 1, ROWS - 1, width).setVerticalAlignment('top');

  columns.forEach(function (c, i) {
    const col = i + 1;
    if (c.note) sh.getRange(1, col).setNote(c.note);
    sh.setColumnWidth(col, c.width);
    applyKind(sh.getRange(2, col, ROWS - 1, 1), c, colLetter(col) + '2');
  });

  if (data.length) sh.getRange(2, 1, data.length, width).setValues(data);

  // Fold the big-event columns behind a "+".
  const firstMore = columns.findIndex(function (c) { return c.more; }) + 1;
  if (firstMore > 0) {
    const n = width - firstMore + 1;
    sh.getRange(1, firstMore, 1, n).shiftColumnGroupDepth(1);
    sh.getRange(1, firstMore, 1, n).setBackground(LOOK.fold);
    sh.setColumnGroupControlPosition(SpreadsheetApp.GroupControlTogglePosition.BEFORE);
    if (!open) sh.getColumnGroup(firstMore, 1).collapse();
  }
}

function buildEvent(sh, values, open) {
  sh.deleteColumns(4, sh.getMaxColumns() - 3);
  const fields = EVENT_MAIN.concat([null], EVENT_MORE); // null: the "More" label row
  if (sh.getMaxRows() > fields.length + 1) sh.deleteRows(fields.length + 2, sh.getMaxRows() - fields.length - 1);

  sh.getRange(1, 1, 1, 3).setValues([['Field', 'Value', '']])
    .setFontWeight('bold').setFontColor(LOOK.headerText).setBackground(LOOK.header);
  sh.setFrozenRows(1);
  sh.setColumnWidth(1, 230);
  sh.setColumnWidth(2, 320);
  sh.setColumnWidth(3, 420);

  let moreRow = 0;
  fields.forEach(function (f, i) {
    const row = i + 2;
    if (!f) {
      moreRow = row;
      sh.getRange(row, 1, 1, 3).setValues([['More (optional)', '', 'Press + on the left to open.']])
        .setFontColor(LOOK.help).setFontStyle('italic').setBackground(LOOK.fold);
      return;
    }
    sh.getRange(row, 1).setValue(f.required ? f.name + ' *' : f.name).setFontWeight('bold');
    sh.getRange(row, 3).setValue(f.help).setFontColor(LOOK.help).setWrap(true);
    applyKind(sh.getRange(row, 2), f, 'B' + row);
    if (values && values[f.name] !== undefined && values[f.name] !== '') sh.getRange(row, 2).setValue(values[f.name]);
  });
  sh.getRange(2, 1, fields.length, 3).setVerticalAlignment('top');
  sh.getRange(1, 1, fields.length + 1, 1).protect().setDescription('Field names: the events app reads these').setWarningOnly(true);

  sh.getRange(moreRow + 1, 1, EVENT_MORE.length, 1).shiftRowGroupDepth(1);
  sh.setRowGroupControlPosition(SpreadsheetApp.GroupControlTogglePosition.BEFORE);
  if (!open) sh.getRowGroup(moreRow + 1, 1).collapse();
}

/** Format and a gentle check for one column or one Event value; `first` is its top cell, e.g. "B2".
 *  Wrong values get a small warning mark, not a pop-up; the app checks everything on Refresh. */
function applyKind(range, c, first) {
  const v = SpreadsheetApp.newDataValidation().setAllowInvalid(true);
  let rule = null;
  switch (c.kind) {
    case 'date':
      range.setNumberFormat('d mmm yyyy');
      rule = v.requireDate().setHelpText('A date, e.g. 15 Nov 2026');
      break;
    case 'time':
      range.setNumberFormat('h:mm am/pm');
      rule = v.requireFormulaSatisfied('=AND(ISNUMBER(' + first + '),' + first + '<1)').setHelpText('A time, e.g. 9:30 or 2:15 pm');
      break;
    case 'datetime':
      range.setNumberFormat('d mmm yyyy h:mm am/pm');
      rule = v.requireDate().setHelpText('e.g. 1 Nov 2026 10:00 am');
      break;
    case 'link':
      range.setNumberFormat('@');
      rule = v.requireFormulaSatisfied('=REGEXMATCH(' + first + ',"^https://")').setHelpText('A link starting https://');
      break;
    case 'email':
      range.setNumberFormat('@');
      rule = v.requireTextIsEmail().setHelpText('An email address');
      break;
    case 'list':
      range.setNumberFormat('@');
      rule = v.requireValueInList(c.values, true).setHelpText('Choose from the list');
      break;
    case 'whole':
      range.setNumberFormat('0');
      rule = v.requireNumberGreaterThan(0).setHelpText('A number above 0');
      break;
    case 'number':
      range.setNumberFormat('0.##');
      rule = v.requireNumberGreaterThanOrEqualTo(0).setHelpText('A number');
      break;
    case 'gap':
      range.setNumberFormat('0');
      rule = v.requireNumberBetween(0, 60).setHelpText('Minutes, 0 to 60');
      break;
    case 'long':
      range.setNumberFormat('@').setWrap(true);
      break;
    default:
      range.setNumberFormat('@');
  }
  if (rule) range.setDataValidation(rule.build());
}

function buildHowTo(sh) {
  sh.setName('How to fill');
  sh.deleteColumns(4, sh.getMaxColumns() - 3);
  sh.deleteRows(13, sh.getMaxRows() - 12);
  sh.setHiddenGridlines(true);
  sh.setColumnWidth(1, 40);
  sh.setColumnWidth(2, 120);
  sh.setColumnWidth(3, 640);
  const lines = [
    ['', 'Event sheet', ''],
    ['', 'Your event\'s agenda, speakers and sponsors, for the NITKSAA events app.', ''],
    ['', '', ''],
    ['1', 'Copy', 'File → Make a copy. Fill in your copy.'],
    ['2', 'Fill in', 'Sessions and Speakers are enough for most events. Use only the tabs you need. Hover over a column name to see what goes in it.'],
    ['3', 'Share', 'Share → add ' + SERVICE_ACCOUNT + ' as Viewer (untick "Notify people").'],
    ['4', 'Link', 'In the events app, paste this sheet\'s link and press Refresh. Change things here, then press Refresh again.'],
    ['', '', ''],
    ['', 'Big events', 'More columns (type, hall, moderator, sponsors presenting…) are folded away: press + above the column letters.'],
    ['', 'Examples', 'See the Breakfast and NITKonnect example sheets for filled-in versions.'],
    ['', '', ''],
    ['', 'Version ' + TEMPLATE_VERSION, ''],
  ];
  sh.getRange(1, 1, lines.length, 3).setValues(lines).setVerticalAlignment('top').setWrap(true);
  sh.getRange('B1').setFontSize(18).setFontWeight('bold');
  sh.getRange('B2:C2').merge().setFontColor(LOOK.help);
  sh.getRange('A4:A7').setFontSize(14).setFontWeight('bold').setHorizontalAlignment('center');
  sh.getRange('B4:B10').setFontWeight('bold');
  sh.getRange('B12').setFontColor(LOOK.help).setFontSize(9);
  sh.getRange(1, 1, lines.length, 3).protect().setDescription('Instructions').setWarningOnly(true);
}

function colLetter(n) {
  let s = '';
  while (n > 0) { const m = (n - 1) % 26; s = String.fromCharCode(65 + m) + s; n = Math.floor((n - 1) / 26); }
  return s;
}
