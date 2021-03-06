#include <stdio.h>
#include <time.h>
#include <math.h>
#include <cuda.h>
#include <cuda_runtime.h>

#define V 200
#define E 100
#define MAX_WEIGHT 1000000
#define TRUE    1
#define FALSE   0

typedef int boolean;
typedef struct
{
        int u;
        int v;

} Edge;

typedef struct
{
        int title;
        boolean visited;

} Vertex;


__device__ __host__ int findEdge(Vertex u, Vertex v, Edge *edges, int *weights)
{

        int i;
        for(i = 0; i < E; i++)
        {

                if(edges[i].u == u.title && edges[i].v == v.title)
                {
                        return weights[i];
                }
        }

        return MAX_WEIGHT;

}

__device__ __host__ void Find_Vertex_CPU(Vertex *vertices, Edge *edges, int *weights, int *length, int *updateLength)
{
        int v;
        int u;

        for(u = 0; u<V; u++){
                if(vertices[u].visited == FALSE){
                        vertices[u].visited = TRUE;
                        for(v = 0; v<V; v++){
                                int weight = findEdge(vertices[u], vertices[v], edges, weights);
                                if(weight < MAX_WEIGHT){
                                        if(updateLength[v]>length[u]+weight){
                                                updateLength[v] = length[u]+weight;
                                        }
                                }
                        }
                }
        }
}


__global__ void Find_Vertex(Vertex *vertices, Edge *edges, int *weights, int *length, int *updateLength)
{

        int u = threadIdx.x;


        if(vertices[u].visited == FALSE)
        {


                vertices[u].visited = TRUE;


                int v;

                for(v = 0; v < V; v++)
                {
                        //Find the weight of the edge
                        int weight = findEdge(vertices[u], vertices[v], edges, weights);

                        //Checks if the weight is a candidate
//Checks if the weight is a candidate
                        if(weight < MAX_WEIGHT)
                        {
                                //If the weight is shorter than the current weight, replace it
                                if(updateLength[v] > length[u] + weight)
                                {
                                        updateLength[v] = length[u] + weight;
                                }
                        }
                }

        }

}
__device__ __host__ void Update_Paths_CPU(Vertex *vertices, int *length, int *updateLength)
{

    int u;
    for(u = 0; u<V; u++){
        if(length[u] > updateLength[u])
        {

            length[u] = updateLength[u];
            vertices[u].visited = FALSE;
        }

        updateLength[u] = length[u];
    }

}
__global__ void Update_Paths(Vertex *vertices, int *length, int *updateLength)
{
        int u = threadIdx.x;
        if(length[u] > updateLength[u])
        {

                length[u] = updateLength[u];
                vertices[u].visited = FALSE;
        }

        updateLength[u] = length[u];


}
void printArray(int *array, FILE *fpo)
{
        int i;
        for(i = 0; i < V; i++)
        {
                if(array[i]!= MAX_WEIGHT){
                        fprintf(fpo, "0 -> %d : %d\n", i, array[i]);
                }
        }
        fclose(fpo);
        printf("stored complete.\n");
}


int main(void)
{
        FILE *fp;
        printf("Reading File\n");
        static char *input_file_name;
        input_file_name = "sample.txt";
        //Read in Graph from a file
        fp = fopen(input_file_name,"r");
        if(!fp)
        {
                printf("Error Reading graph file\n");
                return;
        }

        int source = 0;



        Vertex *vertices;
        Edge *edges;

        int *weights;

        int *len, *updateLength;
        int *len2;


        Vertex *d_V;
        Edge *d_E;
        int *d_W;
        int *d_L;
int sizeV = sizeof(Vertex) * V;
        int sizeE = sizeof(Edge) * E;
        int size = V * sizeof(int);


        float runningTime;
        cudaEvent_t timeStart, timeEnd;


        cudaEventCreate(&timeStart);
        cudaEventCreate(&timeEnd);


        vertices = (Vertex *)malloc(sizeV);
        edges = (Edge *)malloc(sizeE);
        weights = (int *)malloc(E* sizeof(int));
        len = (int *)malloc(size);
        updateLength = (int *)malloc(size);
        len2 = (int *)malloc(size);

        int w[E];
        Edge ed[E];

        int nodestart, nodeend;
        int nodeWeight;
//generate the graph
        for(int i = 0; i<E; i++){
                fscanf(fp, "%d %d %d", &nodestart, &nodeend, &nodeWeight);
                Edge A = { .u = nodestart, .v = nodeend};
                ed[i] = A;
                w[i] = nodeWeight;
        }

        if(fp)
                fclose(fp);
        printf("Read file complete.\n");


        int i = 0;
        for(i = 0; i < V; i++)
        {
                Vertex a = { .title =i , .visited=FALSE};
                vertices[i] = a;
}

        for(i = 0; i < E; i++)
        {
                edges[i] = ed[i];
                weights[i] = w[i];
        }

        cudaMalloc((void**)&d_V, sizeV);
        cudaMalloc((void**)&d_E, sizeE);
        cudaMalloc((void**)&d_W, E * sizeof(int));
        cudaMalloc((void**)&d_L, size);
        cudaMalloc((void**)&d_C, size);

        Vertex root = {source, FALSE};

        root.visited = TRUE;

        len[root.title] = 0;

        updateLength[root.title] = 0;

        cudaMemcpy(d_V, vertices, sizeV, cudaMemcpyHostToDevice);
        cudaMemcpy(d_E, edges, sizeE, cudaMemcpyHostToDevice);
        cudaMemcpy(d_W, weights, E * sizeof(int), cudaMemcpyHostToDevice);
        cudaMemcpy(d_L, len, size, cudaMemcpyHostToDevice);
        cudaMemcpy(d_C, updateLength, size, cudaMemcpyHostToDevice);

        int j;

        for(i = 0; i < V;i++)
        {

                if(vertices[i].title != root.title)
                {
                        len[(int)vertices[i].title] = findEdge(root, vertices[i], edges, weights);
                        updateLength[vertices[i].title] = len[(int)vertices[i].title];
                }
                else{

                        vertices[i].visited = TRUE;
                }
        }
double start, stop;
        double lapse;
        len2 = len;
        start = clock();

        for(i = 0; i < V; i++){

                Find_Vertex_CPU(vertices, edges, weights, len2, updateLength);

                for(j = 0; j < V; j++)
                {
                        Update_Paths_CPU(vertices, len2, updateLength);
                }
        }

        stop = clock();
        lapse = (stop - start)*1000/CLOCKS_PER_SEC;
        FILE *CPUfpo = fopen("CPUresult.txt","w");
        printArray(len2, CPUfpo);



        cudaEventRecord(timeStart, 0);

        cudaMemcpy(d_L, len, size, cudaMemcpyHostToDevice);
        cudaMemcpy(d_C, updateLength, size, cudaMemcpyHostToDevice);


        for(i = 0; i < V; i++){

                        Find_Vertex<<<1, V>>>(d_V, d_E, d_W, d_L, d_C);

                        for(j = 0; j < V; j++)
                        {
                                Update_Paths<<<1,V>>>(d_V, d_L, d_C);
                        }
        }

        cudaEventRecord(timeEnd, 0);
        cudaEventSynchronize(timeEnd);
        cudaEventElapsedTime(&runningTime, timeStart, timeEnd);

        cudaMemcpy(len, d_L, size, cudaMemcpyDeviceToHost);
        FILE *GPUfpo = fopen("GPUresult.txt","w");
        printArray(len, GPUfpo);
int error = 0;
        for(int i = 0; i<E; i++){
                if(len[i]!=len2[i]){
                        error++;
                }
        }

        printf("CPU Running Time: %f ms\n", lapse);
        printf("*******************************");
        printf("\n");
        printf("GPU Running Time: %f ms\n", runningTime);
        printf("The error is: %d\n", error);

        free(vertices);
        free(edges);
        free(weights);
        free(len);
        free(updateLength);
        cudaFree(d_V);
        cudaFree(d_E);
        cudaFree(d_W);
        cudaFree(d_L);
        cudaFree(d_C);
        cudaEventDestroy(timeStart);
        cudaEventDestroy(timeEnd);

}