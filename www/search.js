async function search() {
  var loadingdiv = document.getElementById('loading');
  var noresults = document.getElementById('noresults');
  var resultdiv = document.getElementById('results');
  var searchbox = document.getElementById('search');
  // Clear results before searching
  noresults.style.display = 'none';
  resultdiv.innerHTML = '';
  loadingdiv.style.display = 'block';

  // Get the query from the user
  let query = searchbox.value;
  // Only run a query if the string contains at least two characters
  if (query.length > 1) {
    // Make the HTTP request with the query as a parameter and wait for the JSON results
    let response = await fetch(`${search_endpoint}?q=${query}&size=25`);
    let results = await response.json();
    if (results.length > 0) {
      loadingdiv.style.display = 'none';
      // Iterate through the results and write them to HTML
      resultdiv.innerHTML += `<p>Found ${results.length} results.</p>`;
      results.forEach(item => {
        let url = `https://www.imdb.com/title/${item.id}`;
        let directors = item.directors.join(', ')
        let actors = item.actors.join(', ')
        // Construct the full HTML string that we want to append to the div
        resultdiv.innerHTML += `<div class="result">` +
          `<a href="${url}"><img src="${item.image_url}" onerror="imageError(this)"></a>` +
          `<div><h2><a href="${url}">${item.title}</a></h2><p>Search Score: ${item._search_score}</p><p>IMDB Rating: ${item.rating || '-'}<br/>Director(s): ${directors}<br/>Actors: ${actors}</p><p>${item.year} &mdash; ${item.plot}</p></div></div>`;
      });
    } else {
      noresults.style.display = 'block';
    }
  }
  loadingdiv.style.display = 'none';
}

// Tiny function to catch images that fail to load and replace them
function imageError(image) {
  if (!image.error) {
    image.src = 'no-image.png';
    image.error = 'true'
  }
}

var timer = 0;
document.onreadystatechange = function () {
     if (document.readyState == "complete") {

       var searchbox = document.getElementById('search');
       // Executes the search function 250 milliseconds after user stops typing
       searchbox.addEventListener("keyup", (event) => {
         clearTimeout(timer);
         timer = setTimeout(search, 250);
       });
   }
 }
