// Voor app-tests die JSX-elementen van pagina's opbouwen (t12): de echte React, plus react.cache() als doorgeefluik.
const R = require("react-echt");
module.exports = { ...R, cache: (fn) => fn };
